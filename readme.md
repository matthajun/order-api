
# 🧾 Order API

이 프로젝트는 NestJS, Prisma, SQLite를 기반으로 동작하는 간단한 주문 API입니다.

주어진 코드를 설치하고 실행한 뒤,  
서비스의 성능/구조 개선이 필요한 지점을 파악하고 개선해 주세요.

---

## 🛠 프로젝트 실행 방법

### 1. 패키지 설치
```bash
npm install
```

---

### 2. Prisma 설정
```bash
npx prisma generate
npx prisma migrate dev --name init
```

---

### 3. 기본 데이터 등록 (필수)
```bash
npm run prisma:seed
```

> 사용자 데이터가 없으면 주문을 생성할 수 없습니다.

---

### 4. 서버 실행
```bash
npm run start:dev
```

---

## 📮 API 예시

### 주문 생성
```http
POST http://localhost:3000/orders
Content-Type: application/json

[
  { "userId": 1, "productId": 101, "quantity": 2 },
  { "userId": 2, "productId": 202, "quantity": 1 }
]
```

### 주문 조회
```http
GET http://localhost:3000/orders?userId=1
```

---

## 📋 과제 안내

### 1. 성능 개선
- 이 프로젝트에는 구조적/성능적 개선 여지가 포함되어 있습니다.
- **서비스를 실행하고, 성능 저하 또는 비효율적 설계 포인트를 직접 분석**해 주세요.
- 분석한 문제점에 대해 구체적인 개선을 적용해 주시고,
  가능하다면 개선 전/후의 차이를 설명해 주세요.

### 2. 배포 구성 (옵션널)
- terraform 같은 자동화된 배포 환경 구축
- project root에 **deploy** 폴더를 생성해서 배포 환경 코드를 생성해주세요.
- ecs환경에 auto scale을 지원하는 환경은 필수입니다.
- github 연동을 통한 code-build까지 지원하면 최상입니다.

### 3. 모니터링 환경 구축 (옵션널)
- **system 자원(memory, cpu, open file, ...)**을 모니터링 하는 방법을 제안해주세요. (필수)
- 실제로 모니터링환경을 구축해 주시면 최상입니다.

### 4. 환경 구축 (옵션널)
- 개인 aws 계정을 생성하시고, 배포와 모니터링 환경을 구축해주세요.
- 구축하신 시스템을 확인할 수 있는 권한을 1번 성능 개선 결과와 같이 보내주세요.
- aws 사용료로 50,000원을 지원해드리겠습니다.


