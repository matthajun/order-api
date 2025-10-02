import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
  await prisma.user.createMany({
    data: [
      { id: 1, name: 'Alice' },
      { id: 2, name: 'Bob' },
    ]
  });
}

main().finally(() => prisma.$disconnect());
