import {
  Controller,
  Get,
  Post,
  Body,
  Query,
  BadRequestException,
} from '@nestjs/common';
import { OrderService } from './order.service';
import { GetOrdersRequestDto } from './dtos/get-orders.request.dto';
import { CreateOrdersRequestDto } from './dtos/create-orders.request.dto';

@Controller('orders')
export class OrderController {
  constructor(private readonly orderService: OrderService) {}

  @Get()
  getOrders(@Query() { userId, take = 10, skip = 0 }: GetOrdersRequestDto) {
    return this.orderService.getOrdersByUser(userId, take, skip);
  }

  @Post()
  async createOrders(@Body() dto: CreateOrdersRequestDto) {
    return this.orderService.createOrders(dto.orders);
  }
}
