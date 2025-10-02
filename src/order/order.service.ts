import {BadRequestException, Injectable, InternalServerErrorException, Logger} from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import {
  CreateOrderDto,
  CreateOrderItemDto,
} from './dtos/create-orders.request.dto';

@Injectable()
export class OrderService {
  private readonly logger = new Logger(OrderService.name);
  constructor(private readonly prisma: PrismaService) {}

  async getOrdersByUser(userId: number, take: number, skip: number) {
    const [data, totalCount] = await this.prisma.$transaction([
      this.prisma.user.findUnique({
        where: {id: userId},
        include: {
          orders: {
            take,
            skip,
            orderBy: {id: 'desc'},
            select: {
              id: true,
              productId: true,
              quantity: true,
            },
          },
        },
      }),

      this.prisma.order.count({
        where: {userId: userId},
      }),
    ]);

    return {
      user: {
        id: data.id,
        name: data.name,
      },
      orders: data.orders,
      totalCount,
    };
  }

  async createOrders(orderList: CreateOrderDto[]) {
    // 1. Find users
    const userIds = orderList.map(order => order.userId);
    const userValidationPromises = userIds.map(userId =>
        this.prisma.user.findUnique({
          where: { id: userId },
          select: { id: true }
        })
    );
    const users = await Promise.all(userValidationPromises);
    for (const userId of userIds) {
      if (!users.some(user => user?.id === userId )) {
        this.logger.warn(`This is attempt by Non-existent user ID: ${userId}`);
        throw new BadRequestException(`User with ID ${userId} not found.`);
      }
    }

    // 2. Create order
    const purchaseRecordCreates = orderList.flatMap(
      (orderDto: CreateOrderDto) =>
        orderDto.items.map((itemDto: CreateOrderItemDto) =>
          this.prisma.order.create({
            data: {
              userId: orderDto.userId,
              productId: itemDto.productId,
              quantity: itemDto.quantity,
            },
            select: {
              id: true,
              userId: true,
              productId: true,
              quantity: true,
            },
          }),
        ),
    );

    try {
      const createdPurchaseRecords = await this.prisma.$transaction(
        purchaseRecordCreates,
      );

      return createdPurchaseRecords;
    } catch (error) {
      this.logger.error(`error: ${error}`);
      throw new InternalServerErrorException('Failed to create orders.');
    }
  }
}
