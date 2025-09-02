import { z } from "zod";

export function createOperatorMap() {
  return z.union([
    z.any(),
    z.object({
      $eq: z.any().optional(),
      $ne: z.any().optional(),
      $in: z.any().optional(),
      $nin: z.any().optional(),
      $like: z.any().optional(),
      $ilike: z.any().optional(),
      $re: z.any().optional(),
      $contains: z.any().optional(),
      $gt: z.any().optional(),
      $gte: z.any().optional(),
      $lt: z.any().optional(),
      $lte: z.any().optional(),
    })
  ]);
}