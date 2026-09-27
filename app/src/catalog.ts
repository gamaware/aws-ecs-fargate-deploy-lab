// Fictional stock data for Harbor Goods. The service is read-only and keeps
// the data in memory, so the container never writes to its filesystem.

export interface Product {
  sku: string;
  name: string;
  priceCents: number;
  stock: number;
}

const PRODUCTS: readonly Product[] = Object.freeze([
  { sku: "HG-1001", name: "Canvas tote bag", priceCents: 1800, stock: 240 },
  { sku: "HG-1002", name: "Enamel camp mug", priceCents: 1200, stock: 95 },
  { sku: "HG-1003", name: "Wool watch cap", priceCents: 2400, stock: 0 },
  { sku: "HG-1004", name: "Rope dog leash", priceCents: 3100, stock: 37 },
]);

export const SKU_PATTERN = /^HG-\d{4}$/;

export function listProducts(inStockOnly = false): Product[] {
  return PRODUCTS.filter((p) => !inStockOnly || p.stock > 0).map((p) => ({ ...p }));
}

export function findProduct(sku: string): Product | undefined {
  const product = PRODUCTS.find((p) => p.sku === sku);
  return product === undefined ? undefined : { ...product };
}
