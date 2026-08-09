export type BusinessProfileSaveInput = {
  userId: string;
  companyName: string;
  categories: string[];
  hours: unknown;
  description: string;
  website: string;
  email: string;
  phone: string;
  address: string;
  logoUrl: string | null;
};

/**
 * Business setup must write only to business_profiles.
 * Personal profiles.display_name / bio / avatar_url must not be overwritten.
 */
export function buildBusinessProfileUpsert(input: BusinessProfileSaveInput) {
  return {
    user_id: input.userId,
    company_name: input.companyName || "My Business",
    categories: input.categories,
    hours: input.hours,
    description: input.description,
    website: input.website,
    email: input.email,
    phone: input.phone,
    address: input.address,
    logo_url: input.logoUrl,
  };
}

export function personalProfilePatchFromBusinessSave(): null {
  return null;
}
