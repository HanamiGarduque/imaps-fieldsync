import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const payload = await req.json()
  const record = payload.record
  const oldRecord = payload.old_record

  console.log('Webhook triggered. Record:', JSON.stringify(record))

  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS')!
  const secretKeys = JSON.parse(secretKeysRaw)
  const serviceRoleKey = secretKeys.default

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceRoleKey
  )

  const { data: devices, error } = await supabase
    .from('inspector_device_subscriptions')
    .select('device_token')
    .eq('inspector_id', record.inspector_id)

  console.log('Devices found:', JSON.stringify(devices))
  console.log('Query error:', JSON.stringify(error))

  if (error || !devices?.length) {
    console.log('Skipping: no devices found or query error')
    return new Response(
      JSON.stringify({ skipped: true, reason: error?.message ?? 'no devices found' }),
      { status: 200 }
    )
  }

  const isNewAssignment = !oldRecord
  const message = isNewAssignment
    ? `New inspection assignment: ${record.applicant_name} - ${record.barangay}`
    : `Assignment update: ${record.applicant_name} is now ${record.status}`

  const restApiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!
  const appId = Deno.env.get('ONESIGNAL_APP_ID')!

  console.log('Sending to OneSignal. App ID:', appId)
  console.log('Subscription IDs:', devices.map((d) => d.device_token))

  const oneSignalRes = await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Key ${restApiKey}`,
    },
    body: JSON.stringify({
      app_id: appId,
      include_subscription_ids: devices.map((d) => d.device_token),
      contents: { en: message },
      headings: { en: 'iMAPS FieldSync' },
    }),
  })

  const result = await oneSignalRes.json()
  console.log('OneSignal response status:', oneSignalRes.status)
  console.log('OneSignal response body:', JSON.stringify(result))

  return new Response(JSON.stringify(result), { status: 200 })
})