// Example Next.js App Router API routes for SCATE Community Forum
// Place in app/api/topics/route.ts

import { NextRequest, NextResponse } from 'next/server';

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const lat = searchParams.get('lat');
  const lng = searchParams.get('lng');
  const radius = searchParams.get('radius') || '10000';
  const bubbleId = searchParams.get('bubble_id');

  // Geo-filtered or bubble-filtered topic list
  // Implement with PostGIS ST_DWithin or bubble_id match
  return NextResponse.json({ topics: [] });
}

export async function POST(req: NextRequest) {
  // Host-only: create topic linked to bubble
  const body = await req.json();
  return NextResponse.json({ topic: body }, { status: 201 });
}
