import { Module } from "@medusajs/framework/utils";
import ApprovalModuleService from "./service";
import ApprovalModule from "../modules/approval";

export const APPROVAL_MODULE = "approval";

export default Module(APPROVAL_MODULE, {
  service: ApprovalModuleService,
});