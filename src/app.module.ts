import { Module } from '@nestjs/common';
import { OrderModule } from './order/order.module';
import { PrismaService } from './prisma.service';
import { AppController } from './app.controller';
import { AppService } from './app.service';

@Module({
  imports: [OrderModule],
  providers: [PrismaService, AppService],
  exports: [PrismaService],
  controllers: [AppController],
})
export class AppModule {}
