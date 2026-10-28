// POST /api/comments/[id]/vote
// Body: { vote: 1 } or { vote: -1 }

import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const { vote } = await req.json();
  // Upsert into comment_votes, return like/dislike counts
  return NextResponse.json({ likes: 0, dislikes: 0 });
}
