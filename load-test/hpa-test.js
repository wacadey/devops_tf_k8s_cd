// k6를 사용해 ALB URL에 단계적으로 트래픽을 발생시키는 HPA 실습 스크립트이다.
import http from 'k6/http';
import { check, sleep } from 'k6';

// TARGET_URL은 실행 스크립트에서 환경변수로 전달한다.
// 예: http://example-alb.us-east-1.elb.amazonaws.com/api/cpu
const targetUrl = __ENV.TARGET_URL;

// 환경변수가 없으면 잘못된 주소로 테스트하는 것을 방지하기 위해 즉시 실패시킨다.
if (!targetUrl) {
  throw new Error('TARGET_URL 환경변수가 필요합니다.');
}

export const options = {
  // VU(Virtual User)를 단계적으로 증가시킨 후 0으로 줄인다.
  stages: [
    { duration: '30s', target: 10 },  // 준비 단계: 사용자 10명까지 증가
    { duration: '2m', target: 50 },   // 부하 증가: 사용자 50명 유지
    { duration: '3m', target: 100 },  // 확장 관찰: 사용자 100명 유지
    { duration: '1m', target: 0 },    // 종료 단계: 트래픽을 점진적으로 제거
  ],

  // 테스트 품질 기준이다. 기준을 넘으면 k6가 실패 코드로 종료한다.
  thresholds: {
    http_req_failed: ['rate<0.05'],      // 전체 요청 실패율을 5% 미만으로 유지
    http_req_duration: ['p(95)<2000'],   // 요청의 95%가 2초 이내 응답
  },
};

export default function () {
  // 캐시 영향을 줄이고 요청을 구분하기 위해 timestamp query parameter를 추가한다.
  const response = http.get(`${targetUrl}?t=${Date.now()}`, {
    // 서버 연결을 재사용해 실제 연속 트래픽에 가까운 패턴을 만든다.
    headers: { 'User-Agent': 'de-ai-12-k6-hpa-test' },
    // 단일 요청이 장시간 대기하지 않도록 timeout을 설정한다.
    timeout: '10s',
  });

  // 응답 상태가 정상 범위인지 검사한다.
  check(response, {
    'HTTP status is 2xx': (r) => r.status >= 200 && r.status < 300,
  });

  // 요청 간격을 짧게 두어 CPU 사용량이 충분히 증가하도록 한다.
  sleep(0.1);
}
