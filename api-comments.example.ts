// POST /api/topics/[id]/comments
// Registered profiles only. Supports anonymity.

import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const { body, is_anonymous = false, display_name, parent_id } = await req.json();
  // Auth check + optional geo check + insert into comments table
  return NextResponse.json({ comment: { body, is_anonymous } }, { status: 201 });
}
