import { createProjectResponse } from "../../lib/project-data";

export const dynamic = "force-dynamic";

export async function GET() {
  return createProjectResponse();
}
