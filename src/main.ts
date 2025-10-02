import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { BadRequestException, ValidationPipe } from '@nestjs/common';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  // 전역 Validation pipe
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      transformOptions: { enableImplicitConversion: true },
      exceptionFactory(errors: any) {
        const errorProperties = errors.map((error: any) => error.property);
        let errorMessage = errors.map((error: any) => error.constraints);
        if (errorMessage.length) {
          const errorMessageValue = Object.values(errorMessage[0])[0];
          errorMessage = `Validation failed: ${errorProperties.join(',')}, ${errorMessageValue}`;
        } else {
          errorMessage = `Validation failed: ${errorProperties.join(',')}`;
        }

        return new BadRequestException(errorMessage);
      },
    }),
  );

  await app.listen(3000);
  console.log('Order API (NestJS + Prisma) running on port 3000');
}
bootstrap();
