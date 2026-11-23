import { env } from "cloudflare:workers";
import { handleVisitsGet, handleVisitsPost } from "../../lib/visits";

export const dynamic = "force-dynamic";

function getDatabase() {
  if (!env.DB) throw new Error("counter_database_unavailable");
  return env.DB;
}

export function GET() { return handleVisitsGet(getDatabase); }
export function POST(request: Request) { return handleVisitsPost(request, getDatabase); }
