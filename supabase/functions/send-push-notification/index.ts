import { createClient } from 'jsr:@supabase/supabase-js@2'

// Edge Function: send-push-notification
// Service-to-service authentication via `apikey` header (Supabase Secret API key model).
// Gateway JWT verification is disabled (verify_jwt = false in config.toml);
// authentication is enforced here at the application level instead.

Deno.serve(async (req) => {
  // -------------------------------------------------------------------
  // 1. Authenticate incoming request via `apikey` header
  // -------------------------------------------------------------------
  const incomingApiKeyRaw = req.headers.get('apikey') ?? req.headers.get('x-api-key')
  const incomingApiKey = incomingApiKeyRaw ? incomingApiKeyRaw.trim() : null

  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS')
  const validSecretKeys: string[] = []

  if (secretKeysRaw) {
    try {
      const parsed = JSON.parse(secretKeysRaw)
      if (typeof parsed === 'object' && parsed !== null) {
        for (const val of Object.values(parsed)) {
          if (typeof val === 'string' && val.trim().length > 0) {
            validSecretKeys.push(val.trim())
          }
        }
      } else if (typeof parsed === 'string' && parsed.trim().length > 0) {
        validSecretKeys.push(parsed.trim())
      }
    } catch {
      // If the env var is not valid JSON, treat the raw string value as a key
      if (secretKeysRaw.trim().length > 0) {
        validSecretKeys.push(secretKeysRaw.trim())
      }
    }
  }

  // 1.1 Guard: Server secret configuration must be present
  if (validSecretKeys.length === 0) {
    console.error('Unauthorized webhook invocation: missing or malformed server SUPABASE_SECRET_KEYS configuration')
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // 1.2 Guard: Incoming apikey header must be present
  if (!incomingApiKey) {
    console.error('Unauthorized webhook invocation: missing apikey header')
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // 1.3 Guard: Incoming apikey must match at least one configured secret key
  const isAuthorized = validSecretKeys.some((validKey) => validKey === incomingApiKey)
  if (!isAuthorized) {
    console.error('Unauthorized webhook invocation: invalid or mismatched apikey')
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // -------------------------------------------------------------------
  // 2. Parse the standard Supabase webhook payload
  // -------------------------------------------------------------------
  const payload = await req.json()
  const record = payload.record
  const oldRecord = payload.old_record

  console.log('Webhook received. Event:', payload.type, 'Table:', payload.table)

  // -------------------------------------------------------------------
  // 3. Build privileged Supabase client for internal data queries
  //    (uses the validated secret key)
  // -------------------------------------------------------------------
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    incomingApiKey,
  )

  // -------------------------------------------------------------------
  // 4. Resolve inspector and query device tokens
  // -------------------------------------------------------------------
  const inspectorId = record.assigned_inspector_id ?? record.inspector_id
  if (!inspectorId) {
    return new Response(
      JSON.stringify({ skipped: true, reason: 'no inspector id in record' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const { data: devices, error } = await supabase
    .from('inspector_device_subscriptions')
    .select('device_token')
    .eq('inspector_id', inspectorId)

  if (error || !devices?.length) {
    return new Response(
      JSON.stringify({ skipped: true, reason: error?.message ?? 'no devices found' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  }

  // -------------------------------------------------------------------
  // 5. Build notification message
  // -------------------------------------------------------------------
  const isNewAssignment = !oldRecord
  const applicantName = record.applicant_name ?? 'Inspection Task'
  const barangay = record.barangay ? ` - ${record.barangay}` : ''
  const message = isNewAssignment
    ? `New inspection assignment: ${applicantName}${barangay}`
    : `Assignment update: ${applicantName} is now ${record.status}`

  const restApiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!
  const appId = Deno.env.get('ONESIGNAL_APP_ID')!

  // -------------------------------------------------------------------
  // 6. Dispatch push notification via OneSignal
  // -------------------------------------------------------------------
  const oneSignalRes = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Key ${restApiKey}`,
    },
    body: JSON.stringify({
      app_id: appId,
      include_subscription_ids: devices.map((d: { device_token: string }) => d.device_token),
      contents: { en: message },
      headings: { en: 'iMAPS FieldSync' },
    }),
  })

  const result = await oneSignalRes.json()
  console.log('OneSignal response status:', oneSignalRes.status)

  return new Response(
    JSON.stringify(result),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  )
})
