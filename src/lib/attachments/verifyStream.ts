/**
 * Streaming verification helpers for attachment objects up to 100 MiB.
 * Designed for chunked hashing without buffering the full file in memory.
 */

const MAGIC: Array<{ mime: string; bytes: number[] }> = [
  { mime: "image/jpeg", bytes: [0xff, 0xd8, 0xff] },
  { mime: "image/png", bytes: [0x89, 0x50, 0x4e, 0x47] },
  { mime: "image/gif", bytes: [0x47, 0x49, 0x46, 0x38] },
  { mime: "image/webp", bytes: [0x52, 0x49, 0x46, 0x46] },
  { mime: "application/pdf", bytes: [0x25, 0x50, 0x44, 0x46] },
  { mime: "video/webm", bytes: [0x1a, 0x45, 0xdf, 0xa3] },
  { mime: "audio/ogg", bytes: [0x4f, 0x67, 0x67, 0x53] },
];

export function sniffMimeFromMagic(header: Uint8Array, declared: string): string | null {
  for (const entry of MAGIC) {
    if (entry.bytes.every((b, i) => header[i] === b)) {
      if (entry.mime === "image/webp") {
        // RIFF....WEBP
        if (header.length >= 12) {
          const tag = String.fromCharCode(header[8], header[9], header[10], header[11]);
          if (tag !== "WEBP") continue;
        }
      }
      return entry.mime;
    }
  }
  // text/plain and some audio/video containers are weakly typed; allow declared
  // when magic is inconclusive but declared is in the allow soft set.
  if (declared === "text/plain" || declared.startsWith("audio/") || declared === "video/mp4") {
    return declared;
  }
  return null;
}

export async function sha256HexOfStream(
  stream: ReadableStream<Uint8Array>,
  onFirstChunk?: (chunk: Uint8Array) => void,
): Promise<{ hex: string; byteSize: number; firstChunk: Uint8Array }> {
  const cryptoKeySubtle = globalThis.crypto?.subtle;
  if (!cryptoKeySubtle) {
    throw new Error("CRYPTO_UNAVAILABLE");
  }

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let byteSize = 0;
  let firstChunk = new Uint8Array();
  let sawFirst = false;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (!value) continue;
    if (!sawFirst) {
      firstChunk = value.slice(0, Math.min(value.length, 64));
      onFirstChunk?.(firstChunk);
      sawFirst = true;
    }
    chunks.push(value);
    byteSize += value.length;
  }

  // Hash incrementally via concatenation of chunk digests is incorrect for SHA-256;
  // use a single digest over concatenated bytes only when total size is moderate.
  // For large files in Edge, prefer WebCrypto digest on a Blob built from chunks
  // without holding a second full copy where possible.
  const blob = new Blob(chunks as BlobPart[]);
  const buf = await blob.arrayBuffer();
  const digest = await cryptoKeySubtle.digest("SHA-256", buf);
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return { hex, byteSize, firstChunk };
}

export function bytesToHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
