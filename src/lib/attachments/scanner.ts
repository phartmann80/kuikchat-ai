/**
 * Malware scanner adapter interface.
 * Production AttachmentScanner wiring is gated until vendor DPA/training/webhook
 * confirmation. Test adapter is never the default outside an explicit test env.
 */

export type ScanVerdict = "clean" | "malware" | "suspicious" | "failed" | "pending";

export type ScanRequest = {
  attachmentId: string;
  /** Short-lived service-signed GET URL, or omitted when streaming bytes. */
  objectUrl?: string;
  contentType: string;
  byteSize: number;
  checksumSha256: string;
};

export type ScanResult = {
  verdict: ScanVerdict;
  engine: string;
  externalId?: string;
  failureCode?: string;
  signals?: string[];
};

export interface MalwareScannerAdapter {
  readonly name: string;
  scan(request: ScanRequest): Promise<ScanResult>;
}

/** Deterministic non-production adapter. Never contacts an external vendor. */
export class TestScannerAdapter implements MalwareScannerAdapter {
  readonly name = "test-adapter";

  async scan(request: ScanRequest): Promise<ScanResult> {
    if (request.checksumSha256.endsWith("bad")) {
      return {
        verdict: "malware",
        engine: this.name,
        externalId: `test-${request.attachmentId}`,
        signals: ["TEST_MALWARE"],
      };
    }
    if (request.checksumSha256.endsWith("out")) {
      return {
        verdict: "failed",
        engine: this.name,
        failureCode: "SCANNER_UNAVAILABLE",
      };
    }
    return {
      verdict: "clean",
      engine: this.name,
      externalId: `test-${request.attachmentId}`,
    };
  }
}

/**
 * AttachmentScanner adapter stub — not selected for live use until vendor gate passes.
 * Throws if invoked so production files cannot be sent accidentally.
 */
export class AttachmentScannerAdapter implements MalwareScannerAdapter {
  readonly name = "attachmentscanner-eu";

  async scan(_request: ScanRequest): Promise<ScanResult> {
    throw new Error(
      "AttachmentScanner adapter disabled until vendor gate (DPA/training/webhook) is approved",
    );
  }
}

export type ScannerFactoryOptions = {
  /** Must be true together with kind === "test". Never set in production. */
  allowTest?: boolean;
};

/**
 * Factory: production defaults fail closed (no scanner).
 * Test adapter only when kind="test" AND allowTest=true.
 */
export function createScannerAdapter(
  kind: string | undefined,
  opts: ScannerFactoryOptions = {},
): MalwareScannerAdapter {
  if (kind === "attachmentscanner") {
    return new AttachmentScannerAdapter();
  }
  if (kind === "test") {
    if (!opts.allowTest) {
      throw new Error("TestScannerAdapter rejected outside allowTest environment");
    }
    return new TestScannerAdapter();
  }
  if (kind === "clamav") {
    throw new Error("ClamAV adapter not deployed");
  }
  throw new Error("No production scanner configured");
}

export function mapScanVerdictToWorkerAction(result: ScanResult): "available" | "quarantine" | "fail" {
  if (result.verdict === "clean") return "available";
  if (result.verdict === "malware" || result.verdict === "suspicious") return "quarantine";
  return "fail";
}
