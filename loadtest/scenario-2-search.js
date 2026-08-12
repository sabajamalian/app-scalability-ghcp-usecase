// Scenario 2: order search under load.
//
// Plain k6 JavaScript with no local imports, so this file runs unchanged in
// Azure Load Testing. See docs/azure-load-testing.md.
//
// Local:  make loadtest-2
// Azure:  upload this file, set BASE_URL to your deployed environment

import http from 'k6/http'
import { check } from 'k6'
import { Trend } from 'k6/metrics'

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080'

// Server-side time excluding network and JSON serialization. Under load this
// separates "the database is slow" from "the load generator is the bottleneck".
const serverTime = new Trend('server_time_ms')

export const options = {
  scenarios: {
    order_search: {
      executor: 'constant-vus',
      vus: Number(__ENV.VUS || 20),
      duration: __ENV.DURATION || '30s',
    },
  },
  thresholds: {
    // Expected to FAIL before the index exists and PASS after.
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<150'],
    server_time_ms: ['p(95)<50'],
  },
}

export default function () {
  const response = http.get(
    `${BASE_URL}/api/orders/search?status=SHIPPED&withinHours=48&limit=50`,
  )

  check(response, {
    'status is 200': (r) => r.status === 200,
  })

  if (response.status === 200) {
    try {
      serverTime.add(JSON.parse(response.body).serverMillis)
    } catch {
      // Body was not the expected envelope; the check above already failed.
    }
  }
}
