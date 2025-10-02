import { IsInt, IsOptional } from 'class-validator';
import { Type } from 'class-transformer';

export class GetOrdersRequestDto {
  @Type(() => Number)
  @IsInt()
  userId: number;

  @Type(() => Number)
  @IsInt()
  @IsOptional()
  take: number;

  @Type(() => Number)
  @IsOptional()
  skip: number;
}
