import { strict as assert } from 'node:assert'

// Run with: deno test --no-config --no-lock --allow-env=SUPABASE_SECRET_KEYS,SUPABASE_URL,ONESIGNAL_REST_API_KEY,ONESIGNAL_APP_ID index_test.ts
Deno.test('service webhook authentication, recipient isolation and failure handling', async (t) => {
  const env = {
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: 'test-default-key', supakey: 'test-webhook-key' }),
    SUPABASE_URL: 'https://supabase.example.invalid',
    ONESIGNAL_REST_API_KEY: 'test-onesignal-key',
    ONESIGNAL_APP_ID: 'test-app-id',
  }
  const previous = Object.fromEntries(Object.keys(env).map((key) => [key, Deno.env.get(key)]))
  const originalServe = Object.getOwnPropertyDescriptor(Deno, 'serve')!
  const originalFetch = globalThis.fetch
  let handler: (req: Request) => Response | Promise<Response> = () => { throw new Error('Handler not registered') }
  const requests: Request[] = []
  let devices: unknown = [{ device_token: 'test-subscription' }]
  let databaseStatus = 200
  let pushStatus = 200
  let pushBody = JSON.stringify({ id: 'test-message-id', subscription_ids: ['private-subscription-detail'] })
  let networkFailure = false

  const payload = {
    type: 'INSERT', schema: 'public', table: 'field_jobs', old_record: null,
    record: {
      assigned_inspector_id: '11111111-1111-4111-8111-111111111111',
      inspector_id: '22222222-2222-4222-8222-222222222222',
      applicant_name: 'Test Applicant', barangay: 'Test Barangay', status: 'pending',
    },
  }
  const invoke = (body: unknown = payload, key: string | null = 'test-webhook-key', method = 'POST', header = 'apikey') => {
    const headers = new Headers({ 'Content-Type': 'application/json' })
    if (key !== null) headers.set(header, key)
    return handler(new Request('https://function.example.invalid', {
      method, headers, ...(method === 'GET' ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }),
    }))
  }

  try {
    for (const [key, value] of Object.entries(env)) Deno.env.set(key, value)
    Object.defineProperty(Deno, 'serve', { configurable: true, value: (callback: typeof handler) => { handler = callback } })
    globalThis.fetch = async (input, init) => {
      const req = new Request(input, init)
      requests.push(req)
      const url = new URL(req.url)
      if (url.origin === env.SUPABASE_URL && url.pathname === '/rest/v1/inspector_device_subscriptions') {
        assert.equal(req.method, 'GET')
        assert.equal(url.searchParams.get('select'), 'device_token')
        return Response.json(devices, { status: databaseStatus })
      }
      assert.equal(req.url, 'https://onesignal.com/api/v1/notifications')
      assert.equal(req.method, 'POST')
      assert.equal(req.headers.get('Authorization'), 'Key test-onesignal-key')
      if (networkFailure) throw new Error('sensitive upstream network details')
      return new Response(pushBody, { status: pushStatus, headers: { 'Content-Type': 'application/json' } })
    }
    await import('./index.ts')

    await t.step('fails closed for missing, wrong, anon and user-JWT credentials', async () => {
      for (const key of [null, 'wrong-key', 'test-anon-key']) assert.equal((await invoke(payload, key)).status, 401)
      assert.equal((await invoke(payload, 'Bearer test-user-jwt', 'POST', 'Authorization')).status, 401)
      Deno.env.delete('SUPABASE_SECRET_KEYS')
      assert.equal((await invoke()).status, 401)
      Deno.env.set('SUPABASE_SECRET_KEYS', '{}')
      assert.equal((await invoke()).status, 401)
      Deno.env.set('SUPABASE_SECRET_KEYS', env.SUPABASE_SECRET_KEYS)
      assert.equal(requests.length, 0)
    })
    await t.step('rejects unsupported methods and malformed webhook payloads before external requests', async () => {
      assert.equal((await invoke(payload, 'test-webhook-key', 'GET')).status, 405)
      for (const body of ['{', null, [], {}, { ...payload, record: null }, { ...payload, record: [] },
        { ...payload, type: 'DELETE' }, { ...payload, type: ['UPDATE'], old_record: payload.record },
        { ...payload, schema: 'private' }, { ...payload, table: 'profiles' }, { ...payload, table: ['field_jobs'] },
        { ...payload, old_record: [] }, { ...payload, record: { assigned_inspector_id: {} } },
        { ...payload, record: { assigned_inspector_id: 'not-a-uuid' } },
        { ...payload, record: { ...payload.record, applicant_name: {} } }]) {
        assert.equal((await invoke(body)).status, 400)
      }
      assert.equal(requests.length, 0)
    })
    await t.step('named keys select only the assigned inspector subscription and preserve notification copy', async () => {
      const response = await invoke()
      assert.equal(response.status, 200)
      assert.equal(response.headers.get('Access-Control-Allow-Origin'), null)
      assert.deepEqual(await response.json(), { id: 'test-message-id' })
      assert.equal(new URL(requests[0].url).searchParams.get('inspector_id'), 'eq.' + payload.record.assigned_inspector_id)
      assert.equal(requests[0].headers.get('apikey'), 'test-webhook-key')
      assert.deepEqual(await requests[1].json(), {
        app_id: 'test-app-id', include_subscription_ids: ['test-subscription'],
        contents: { en: 'New inspection assignment: Test Applicant - Test Barangay' }, headings: { en: 'iMAPS FieldSync' },
      })
      requests.length = 0
      const update = { ...payload, type: 'UPDATE', table: 'application_status_tracks', old_record: payload.record,
        record: { inspector_id: payload.record.inspector_id, status: 'completed' } }
      assert.equal((await invoke(update, 'test-default-key', 'POST', 'x-api-key')).status, 200)
      assert.equal(new URL(requests[0].url).searchParams.get('inspector_id'), 'eq.' + payload.record.inspector_id)
      assert.equal((await requests[1].json()).contents.en, 'Assignment update: Inspection Task is now completed')
      requests.length = 0
    })
    await t.step('keeps no-recipient and no-subscription skips without broadcasting', async () => {
      assert.equal((await invoke({ ...payload, record: {} })).status, 200)
      assert.equal(requests.length, 0)
      devices = []
      const response = await invoke()
      assert.equal(response.status, 200)
      assert.equal((await response.json()).skipped, true)
      assert.equal(requests.length, 1)
      devices = [{ device_token: 'test-subscription' }]
      requests.length = 0
    })
    await t.step('configuration, database and push failures never expose upstream details or report success', async () => {
      Deno.env.delete('SUPABASE_URL')
      assert.equal((await invoke()).status, 500)
      Deno.env.set('SUPABASE_URL', env.SUPABASE_URL)
      Deno.env.delete('ONESIGNAL_REST_API_KEY')
      assert.equal((await invoke()).status, 500)
      Deno.env.set('ONESIGNAL_REST_API_KEY', env.ONESIGNAL_REST_API_KEY)
      Deno.env.delete('ONESIGNAL_APP_ID')
      assert.equal((await invoke()).status, 500)
      Deno.env.set('ONESIGNAL_APP_ID', env.ONESIGNAL_APP_ID)
      databaseStatus = 400
      devices = { message: 'sensitive database details' }
      let response = await invoke()
      assert.equal(response.status, 502)
      assert.deepEqual(await response.json(), { error: 'Device lookup failed' })
      databaseStatus = 200
      devices = [{ device_token: 'test-subscription' }]
      pushStatus = 403
      pushBody = JSON.stringify({ errors: ['sensitive OneSignal details'] })
      response = await invoke()
      assert.equal(response.status, 502)
      assert.deepEqual(await response.json(), { error: 'Notification dispatch failed' })
      pushStatus = 200
      pushBody = 'not json'
      assert.equal((await invoke()).status, 502)
      networkFailure = true
      response = await invoke()
      assert.equal(response.status, 502)
      assert.deepEqual(await response.json(), { error: 'Notification dispatch failed' })
    })
  } finally {
    Object.defineProperty(Deno, 'serve', originalServe)
    globalThis.fetch = originalFetch
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key)
      else Deno.env.set(key, value)
    }
  }
})
