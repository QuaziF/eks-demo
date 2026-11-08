// Ramp up, hold, ramp down. Each request burns CPU on the pod that serves it, so load on the
// pods (and therefore the HPA) follows the number of virtual users.
//
//   BASE_URL=http://localhost:8080 k6 run loadtest/k6.js
//   BASE_URL=http://<alb-dns-name> WORK_MS=30 k6 run loadtest/k6.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const WORK_MS = __ENV.WORK_MS || '30';
// How long the full load is held. A new node takes 2 to 3 minutes to join, so for the Cluster
// Autoscaler run use HOLD=240s to still have load when it arrives.
const HOLD = __ENV.HOLD || '90s';

export const options = {
  stages: [
    { duration: '45s', target: 20 },
    { duration: '45s', target: 60 },
    { duration: HOLD, target: 60 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],
  },
};

export default function () {
  const res = http.get(`${BASE}/work?ms=${WORK_MS}`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.05);
}
