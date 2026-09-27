import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@6";

type Delivery = {
  id: string;
  event_id: string;
  user_id: string;
  delivery_mode: "instant" | "daily_digest";
};

type Activity = {
  id: string;
  group_id: string;
  idea_id: string | null;
  kind: string;
  metadata: { title?: string; group_name?: string };
  actor: { display_name: string };
  group: { name: string };
};

type DeviceToken = {
  id: string;
  user_id: string;
  token: string;
  environment: "sandbox" | "production";
};

const required = (name: string): string => {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const supabase = createClient(required("SUPABASE_URL"), required("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false, autoRefreshToken: false },
});

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "POST required" });
  const expected = required("DISPATCH_SECRET");
  if (request.headers.get("authorization") !== `Bearer ${expected}`) return json(401, { error: "Unauthorized" });

  try {
    const { data, error } = await supabase.rpc("claim_notification_deliveries", { batch_size: 100 });
    if (error) throw error;
    const deliveries = (data ?? []) as Delivery[];
    if (deliveries.length === 0) return json(200, { claimed: 0, sent: 0 });

    const eventIDs = [...new Set(deliveries.map((item) => item.event_id))];
    const userIDs = [...new Set(deliveries.map((item) => item.user_id))];
    const [{ data: eventData, error: eventError }, { data: tokenData, error: tokenError }] = await Promise.all([
      supabase.from("activity_events")
        .select("id,group_id,idea_id,kind,metadata,actor:profiles!activity_events_actor_id_fkey(display_name),group:groups(name)")
        .in("id", eventIDs),
      supabase.from("device_tokens").select("id,user_id,token,environment").in("user_id", userIDs),
    ]);
    if (eventError) throw eventError;
    if (tokenError) throw tokenError;

    const activities = new Map((eventData as Activity[]).map((event) => [event.id, event]));
    const tokens = tokenData as DeviceToken[];
    const instant = deliveries.filter((item) => item.delivery_mode === "instant").map((item) => [item]);
    const digestByUser = new Map<string, Delivery[]>();
    for (const item of deliveries.filter((candidate) => candidate.delivery_mode === "daily_digest")) {
      digestByUser.set(item.user_id, [...(digestByUser.get(item.user_id) ?? []), item]);
    }
    const batches = [...instant, ...digestByUser.values()];
    let sent = 0;

    for (const batch of batches) {
      const deliveryIDs = batch.map((item) => item.id);
      const userID = batch[0].user_id;
      const events = batch.map((item) => activities.get(item.event_id)).filter(Boolean) as Activity[];
      try {
        const userTokens = tokens.filter((token) => token.user_id === userID);
        if (userTokens.length > 0 && events.length > 0) {
          const content = notificationContent(events, batch[0].delivery_mode);
          const results = await Promise.all(userTokens.map((token) => sendToAPNs(token, content)));
          if (!results.some((result) => result.ok)) {
            throw new Error(results.map((result) => result.reason).filter(Boolean).join(", ") || "APNs rejected every device");
          }
          sent += results.filter((result) => result.ok).length;
        }
        await finish(deliveryIDs, null);
      } catch (error) {
        await finish(deliveryIDs, error instanceof Error ? error.message : String(error));
      }
    }
    return json(200, { claimed: deliveries.length, sent });
  } catch (error) {
    console.error(error);
    return json(500, { error: "Notification dispatch failed" });
  }
});

function notificationContent(events: Activity[], mode: Delivery["delivery_mode"]) {
  const first = events[0];
  const deepLink = first.idea_id
    ? `crewpick://group/${first.group_id}/idea/${first.idea_id}`
    : `crewpick://group/${first.group_id}`;
  if (mode === "daily_digest") {
    const groupCount = new Set(events.map((event) => event.group_id)).size;
    return {
      title: "Your CrewPick digest",
      body: `${events.length} update${events.length === 1 ? "" : "s"} across ${groupCount} group${groupCount === 1 ? "" : "s"}`,
      deepLink,
      collapseID: `digest-${first.group_id}`,
    };
  }
  const subject = first.metadata.title ?? first.metadata.group_name ?? first.group.name;
  const verb = first.kind === "ideaAdded" ? "added"
    : first.kind === "commentAdded" ? "commented on"
    : first.kind === "planCreated" ? "planned"
    : first.kind === "planCompleted" ? "completed"
    : first.kind === "memberJoined" ? "joined"
    : "updated";
  return {
    title: first.group.name,
    body: `${first.actor.display_name} ${verb} ${subject}`,
    deepLink,
    collapseID: first.id,
  };
}

async function providerToken() {
  const privateKey = required("APNS_PRIVATE_KEY").replaceAll("\\n", "\n");
  const key = await importPKCS8(privateKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: required("APNS_KEY_ID") })
    .setIssuer(required("APNS_TEAM_ID"))
    .setIssuedAt()
    .sign(key);
}

async function sendToAPNs(token: DeviceToken, content: ReturnType<typeof notificationContent>) {
  const host = token.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${token.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": required("APNS_TOPIC"),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 86_400),
      "apns-collapse-id": content.collapseID.slice(0, 64),
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: { alert: { title: content.title, body: content.body }, sound: "default" },
      deep_link: content.deepLink,
    }),
  });
  const payload = response.status === 200 ? null : await response.json().catch(() => null) as { reason?: string } | null;
  if (response.status === 410 || payload?.reason === "BadDeviceToken" || payload?.reason === "Unregistered") {
    await supabase.from("device_tokens").delete().eq("id", token.id);
  }
  return { ok: response.status === 200, reason: payload?.reason ?? (response.status === 200 ? undefined : `APNs ${response.status}`) };
}

async function finish(ids: string[], failure: string | null) {
  const { error } = await supabase.rpc("finish_notification_deliveries", {
    delivery_ids: ids,
    failure,
  });
  if (error) throw error;
}
