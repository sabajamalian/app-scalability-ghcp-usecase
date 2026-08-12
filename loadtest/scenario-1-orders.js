// Scenario 1: order listing under load.
//
// This script is intentionally plain k6 JavaScript with no local imports, so
// the same file runs unchanged in Azure Load Testing (which supports k6 as a
// test engine). See docs/azure-load-testing.md.
//
// Local:  make loadtest-1
// Azure:  upload this file, set BASE_URL to your deployed environment

import http from 'k6/http'
import { check } from 'k6'
import { Trend } from 'k6/metrics'

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080'

// Tracks the SQL statement count the backend reports for each response. This is
// the number scenario 1 is about, and watching it as a load-test metric rather
// than a log line makes the fix impossible to argue with.
const sqlQueries = new Trend('sql_queries_per_request')

export const options = {
  scenarios: {
    order_listing: {
      executor: 'constant-vus',
      vus: Number(__ENV.VUS || 20),
      duration: __ENV.DURATION || '30s',
    },
  },
  thresholds: {
    // These are the gate. They are expected to FAIL before the fix and PASS
    // after it. Do not soften them to make the run go green; that is the exact
    // habit this demo argues against.
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<150'],
    sql_queries_per_request: ['avg<5'],
  },
}

export default function () {
  const response = http.get(`${BASE_URL}/api/orders?limit=50`)

  check(response, {
    'status is 200': (r) => r.status === 200,
    'returned rows': (r) => {
      try {
        return JSON.parse(r.body).data.length > 0
      } catch {
        return false
      }
    },
  })

  if (response.status === 200) {
    try {
      sqlQueries.add(JSON.parse(response.body).sqlQueryCount)
    } catch {
      // Body was not the expected envelope; the check above already failed.
    }
  }
}
