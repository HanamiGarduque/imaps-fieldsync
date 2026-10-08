import { createClient } from 'jsr:@supabase/supabase-js@2'

// Service-to-service webhook: verify_jwt is false; configured secret keys
// authenticate pg_net. User JWTs and publishable/anon keys are not accepted.
Deno.serve(async (req) => {
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
      // Preserve the historical raw-secret environment format.
      if (secretKeysRaw.trim().length > 0) validSecretKeys.push(secretKeysRaw.trim())
    }
  }

  if (!incomingApiKey || !validSecretKeys.includes(incomingApiKey)) {
    console.error('Unauthorized webhook invocation: missing or invalid secret key')
    return Response.json({ error: 'Unauthorized' }, { status: 401 })
  }
  if (req.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405, headers: { Allow: 'POST' } })
  }

  let payload: unknown
  try {
    payload = await req.json()
  } catch {
    return Response.json({ error: 'Invalid webhook payload' }, { status: 400 })
  }
  const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)
  if (!isRecord(payload) || !isRecord(payload.record) || payload.schema !== 'public' ||
      (payload.table !== 'field_jobs' && payload.table !== 'application_status_tracks') ||
      (payload.type !== 'INSERT' && payload.type !== 'UPDATE') ||
      (payload.type === 'INSERT' ? payload.old_record !== null : !isRecord(payload.old_record))) {
    return Response.json({ error: 'Invalid webhook payload' }, { status: 400 })
  }
  const record = payload.record
  const oldRecord = payload.old_record
  const inspectorId = record.assigned_inspector_id ?? record.inspector_id
  if ((inspectorId != null && (typeof inspectorId !== 'string' ||
      !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(inspectorId))) ||
      ['applicant_name', 'barangay', 'status'].some((key) => record[key] != null && typeof record[key] !== 'string')) {
    return Response.json({ error: 'Invalid webhook payload' }, { status: 400 })
  }
  console.log('Webhook received. Event:', payload.type, 'Table:', payload.table)
  if (!inspectorId) {
    return Response.json({ skipped: true, reason: 'no inspector id in record' })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const restApiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')
  const appId = Deno.env.get('ONESIGNAL_APP_ID')
  if (!supabaseUrl || !restApiKey || !appId) {
    console.error('Missing notification server configuration')
    return Response.json({ error: 'Server configuration error' }, { status: 500 })
  }

  try {
    // Only the authenticated database webhook supplies recipient identity.
    // Keep the privileged query read-only and scoped to that inspector.
    const supabase = createClient(supabaseUrl, incomingApiKey)
    const { data: devices, error } = await supabase
      .from('inspector_device_subscriptions')
      .select('device_token')
      .eq('inspector_id', inspectorId)

    if (error) {
      console.error('Device subscription lookup failed')
      return Response.json({ error: 'Device lookup failed' }, { status: 502 })
    }
    if (!devices?.length) {
      return Response.json({ skipped: true, reason: 'no devices found' })
    }

    const isNewAssignment = !oldRecord
    const applicantName = record.applicant_name ?? 'Inspection Task'
    const barangay = record.barangay ? ` - ${record.barangay}` : ''
    const message = isNewAssignment
      ? `New inspection assignment: ${applicantName}${barangay}`
      : `Assignment update: ${applicantName} is now ${record.status}`

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
    console.log('OneSignal response status:', oneSignalRes.status)
    if (!oneSignalRes.ok) {
      await oneSignalRes.body?.cancel()
      return Response.json({ error: 'Notification dispatch failed' }, { status: 502 })
    }
    const result = await oneSignalRes.json()
    // Return the receipt, never raw upstream errors or subscription details.
    return Response.json({ id: typeof result?.id === 'string' ? result.id : null })
  } catch {
    console.error('Notification dispatch failed')
    return Response.json({ error: 'Notification dispatch failed' }, { status: 502 })
  }
})
