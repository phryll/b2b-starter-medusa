import { z } from "zod";

// Re-export commonly used Medusa validators
export { z };

// Helper for strict objects (Medusa compatibility)
export const createStrictObject = <T extends z.ZodRawShape>(shape: T) => {
  return z.object(shape).strict();
};

// Helper for select params
export const createSelectParams = () => {
  return z.object({
    fields: z.string().optional(),
  });
};