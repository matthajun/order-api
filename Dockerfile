FROM node:22-alpine AS builder

WORKDIR /app

RUN apk add --no-cache openssl-dev

COPY package.json package-lock.json ./

RUN npm install

COPY . .

RUN npm run build

RUN npx prisma generate

################################
FROM node:22-alpine AS runner

RUN apk add --no-cache openssl

WORKDIR /app

COPY --from=builder /app/prisma/schema.prisma /app/prisma/schema.prisma
COPY --from=builder /app/node_modules ./node_modules

COPY --from=builder /app/prisma/orders.db /app/prisma/orders.db

COPY --from=builder /app/dist ./dist

ENTRYPOINT ["/bin/sh", "-c", "node ./dist/main"]