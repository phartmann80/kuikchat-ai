/**
 * Historical E2E-encryption UI removed: message bodies are stored as plaintext
 * at the application/database layer. Do not reintroduce end-to-end encryption
 * claims until a real E2E design is implemented and verified.
 */

interface EncryptionBannerProps {
  contactName?: string;
}

/** @deprecated No-op; false E2E claim removed. */
export const EncryptionBanner = (_props: EncryptionBannerProps) => null;

/** @deprecated No-op; false encryption claim removed. */
export const EncryptionIndicator = () => null;
