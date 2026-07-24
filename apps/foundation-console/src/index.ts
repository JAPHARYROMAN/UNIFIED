import { create } from "@bufbuild/protobuf";

import {
  AssetIdSchema,
  MoneySchema,
} from "../../../packages/generated/typescript/unified/v1/types_pb.js";

export function foundationAmount(units: string) {
  return create(MoneySchema, {
    assetId: create(AssetIdSchema, { value: "asset:local:usd" }),
    units,
  });
}

const amount = foundationAmount("1000");
if (amount.units !== "1000") {
  throw new Error("generated money binding did not preserve exact units");
}

