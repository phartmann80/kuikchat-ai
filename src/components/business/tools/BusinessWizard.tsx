import React, { useState, useEffect, useRef } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  ChevronRight,
  Camera,
  Loader2,
  Store,
  SwitchCamera,
  Building2,
  Clock,
  MapPin,
  Mail,
  Globe,
  Phone,
  Check,
} from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useProfile } from "@/hooks/useProfile";
import { buildBusinessProfileUpsert } from "@/lib/businessProfileSave";
import { toast } from "sonner";

interface BusinessWizardProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const CATEGORIES = [
  "Other business",
  "Shopping & retail",
  "Arts & entertainment",
  "Beauty, cosmetic & personal care",
  "Local service",
  "Finance",
  "Travel and transport",
  "Vehicle, aircraft and boat",
  "Non-profit organisation",
  "Residence",
  "Restaurant",
  "Education",
];

type DayHours = { open: string; close: string; enabled: boolean };
type BusinessHours = Record<string, DayHours[]>;

const DAYS = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

const initialHours: BusinessHours = DAYS.reduce((acc, day) => {
  acc[day] = [{ open: "09:00", close: "17:00", enabled: false }];
  return acc;
}, {} as BusinessHours);

export const BusinessWizard = ({ open, onOpenChange }: BusinessWizardProps) => {
  const { user } = useAuth();
  const { refetch: refetchUserProfile } = useProfile();
  
  // Wizard state
  const [step, setStep] = useState(1);
  const [loading, setLoading] = useState(false);
  const [fetching, setFetching] = useState(true);

  // Form Fields State
  const [companyName, setCompanyName] = useState("");
  const [selectedCategories, setSelectedCategories] = useState<string[]>([]);
  const [hoursMode, setHoursMode] = useState<"selected" | "always" | "appointment">("always");
  const [hoursDetails, setHoursDetails] = useState<BusinessHours>(initialHours);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [description, setDescription] = useState("");
  const [website, setWebsite] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [address, setAddress] = useState("");

  // Sub-navigation within hours step
  const [isEditingHoursDetail, setIsEditingHoursDetail] = useState(false);

  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  // Fetch existing business profile on mount
  useEffect(() => {
    const fetchBusinessProfile = async () => {
      if (!user) return;
      setFetching(true);
      try {
        const { data, error } = await supabase
          .from("business_profiles")
          .select("*")
          .eq("user_id", user.id)
          .maybeSingle();

        if (error) throw error;

        if (data) {
          setCompanyName(data.company_name || "");
          setSelectedCategories(data.categories || []);
          setDescription(data.description || "");
          setWebsite(data.website || "");
          setEmail(data.email || "");
          setPhone(data.phone || "");
          setAddress(data.address || "");
          setAvatarUrl(data.logo_url || null);
          
          if (data.hours) {
            // Restore hours mode if saved
            const hoursData = data.hours as unknown as {
              mode?: "selected" | "always" | "appointment";
              details?: BusinessHours;
            };
            if (hoursData.mode) {
              setHoursMode(hoursData.mode);
            }
            if (hoursData.details) {
              setHoursDetails(hoursData.details);
            }
          }
        }
      } catch (err) {
        console.error("Error fetching business profile:", err);
      } finally {
        setFetching(false);
      }
    };

    if (open) {
      setStep(1);
      fetchBusinessProfile();
    }
  }, [open, user]);

  const handleCategoryToggle = (category: string) => {
    setSelectedCategories((prev) => {
      if (prev.includes(category)) {
        return prev.filter((c) => c !== category);
      }
      if (prev.length >= 3) {
        toast.warning("You can select up to 3 categories");
        return prev;
      }
      return [...prev, category];
    });
  };

  const handleAvatarClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;

    if (!file.type.startsWith("image/")) {
      toast.error("Please upload an image file");
      return;
    }

    setUploading(true);
    const fileExt = file.name.split(".").pop();
    const filePath = `${user.id}/business_logo_${Date.now()}.${fileExt}`;

    try {
      const { error: uploadError } = await supabase.storage
        .from("avatars")
        .upload(filePath, file, { upsert: true });

      if (uploadError) throw uploadError;

      const { data: urlData } = supabase.storage
        .from("avatars")
        .getPublicUrl(filePath);

      const publicUrl = `${urlData.publicUrl}?t=${Date.now()}`;
      setAvatarUrl(publicUrl);
      toast.success("Logo uploaded successfully");
    } catch (err) {
      console.error(err);
      toast.error("Failed to upload logo");
    } finally {
      setUploading(false);
    }
  };

  const handleSave = async () => {
    if (!user) return;
    setLoading(true);

    const businessData = buildBusinessProfileUpsert({
      userId: user.id,
      companyName,
      categories: selectedCategories,
      hours: {
        mode: hoursMode,
        details: hoursDetails,
      },
      description,
      website,
      email,
      phone,
      address,
      logoUrl: avatarUrl,
    });

    try {
      // Upsert business profile only — never overwrite personal identity fields.
      const { error: upsertError } = await supabase
        .from("business_profiles")
        .upsert(businessData);

      if (upsertError) throw upsertError;

      toast.success("Business profile saved successfully!");
      refetchUserProfile();
      onOpenChange(false);
    } catch (err) {
      console.error("Error saving business profile:", err);
      toast.error("Failed to save profile");
    } finally {
      setLoading(false);
    }
  };

  const renderHoursEditor = () => {
    return (
      <div className="space-y-4">
        <div className="flex items-center justify-between border-b border-white/10 pb-3">
          <button
            onClick={() => setIsEditingHoursDetail(false)}
            className="text-sm font-semibold text-muted-foreground hover:text-white"
          >
            Cancel
          </button>
          <h3 className="text-base font-bold">Business hours</h3>
          <button
            onClick={() => setIsEditingHoursDetail(false)}
            className="text-sm font-semibold text-emerald-500 hover:text-emerald-400"
          >
            Save
          </button>
        </div>

        <div className="space-y-4 max-h-[400px] overflow-y-auto pr-1">
          {DAYS.map((day) => {
            const dayHour = hoursDetails[day]?.[0] || { open: "09:00", close: "17:00", enabled: false };
            return (
              <div key={day} className="flex items-center justify-between py-2 border-b border-white/5">
                <div>
                  <p className="text-sm font-medium text-white">{day}</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    {dayHour.enabled ? "Open 24 hours" : "Closed"}
                  </p>
                </div>
                <Switch
                  checked={dayHour.enabled}
                  onCheckedChange={(checked) => {
                    setHoursDetails((prev) => ({
                      ...prev,
                      [day]: [{ ...dayHour, enabled: checked }],
                    }));
                  }}
                  className="data-[state=checked]:bg-emerald-500"
                />
              </div>
            );
          })}
        </div>
      </div>
    );
  };

  const renderStep = () => {
    switch (step) {
      case 1:
        // Step 1: Business Name
        return (
          <div className="space-y-5 py-4">
            <div className="space-y-2">
              <Label htmlFor="companyName" className="text-sm font-medium text-white">
                Business Name
              </Label>
              <Input
                id="companyName"
                value={companyName}
                onChange={(e) => setCompanyName(e.target.value)}
                placeholder="Enter your business name"
                className="bg-[#1f2c34] border-white/10 text-white rounded-xl focus:border-emerald-500 focus:ring-emerald-500/20"
              />
            </div>
            <p className="text-xs text-muted-foreground leading-relaxed">
              This name will be shown on your public business profile and will help customers search for your shop.
            </p>
          </div>
        );

      case 2:
        // Step 2: Select business category (2.jpg)
        return (
          <div className="space-y-6 py-4">
            <div>
              <h3 className="text-lg font-bold text-white mb-2">Select your business category</h3>
              <p className="text-xs text-muted-foreground">
                Choose up to three categories to show on your business profile.
              </p>
            </div>

            <div className="flex flex-wrap gap-2.5 max-h-[300px] overflow-y-auto pr-1">
              {CATEGORIES.map((cat) => {
                const isSelected = selectedCategories.includes(cat);
                return (
                  <button
                    key={cat}
                    onClick={() => handleCategoryToggle(cat)}
                    className={`text-xs px-4 py-2.5 rounded-full border transition-all ${
                      isSelected
                        ? "border-emerald-500 bg-emerald-500/10 text-emerald-400 font-semibold"
                        : "border-white/10 bg-[#1f2c34] text-white/90 hover:bg-[#2c3e4a]"
                    }`}
                  >
                    {cat}
                  </button>
                );
              })}
            </div>
            <p className="text-xs text-emerald-500 font-semibold hover:underline cursor-pointer">
              + See more categories
            </p>
          </div>
        );

      case 3:
        // Step 3: Add your business hours (5.jpg / 6.jpg)
        if (isEditingHoursDetail) {
          return renderHoursEditor();
        }
        return (
          <div className="space-y-6 py-4">
            <div>
              <h3 className="text-lg font-bold text-white mb-2">Add your business hours</h3>
              <p className="text-xs text-muted-foreground">
                Let customers know when you open and close each day.
              </p>
            </div>

            <div className="space-y-1 bg-[#1f2c34] rounded-xl overflow-hidden border border-white/5">
              <button
                onClick={() => {
                  setHoursMode("selected");
                  setIsEditingHoursDetail(true);
                }}
                className={`w-full flex items-center justify-between px-4 py-4 border-b border-white/5 hover:bg-white/5 text-left ${
                  hoursMode === "selected" ? "bg-white/5" : ""
                }`}
              >
                <div>
                  <p className="text-sm font-semibold text-white">Open for selected hours</p>
                  <p className="text-xs text-muted-foreground mt-0.5">Customize daily schedule</p>
                </div>
                <div className="flex items-center gap-2">
                  {hoursMode === "selected" && <Check className="w-4 h-4 text-emerald-500" />}
                  <ChevronRight className="w-4 h-4 text-muted-foreground" />
                </div>
              </button>

              <button
                onClick={() => setHoursMode("always")}
                className={`w-full flex items-center justify-between px-4 py-4 border-b border-white/5 hover:bg-white/5 text-left ${
                  hoursMode === "always" ? "bg-white/5" : ""
                }`}
              >
                <div>
                  <p className="text-sm font-semibold text-white">Always open</p>
                  <p className="text-xs text-muted-foreground mt-0.5">Open 24 hours, 7 days a week</p>
                </div>
                {hoursMode === "always" && <Check className="w-4 h-4 text-emerald-500" />}
              </button>

              <button
                onClick={() => setHoursMode("appointment")}
                className={`w-full flex items-center justify-between px-4 py-4 hover:bg-white/5 text-left ${
                  hoursMode === "appointment" ? "bg-white/5" : ""
                }`}
              >
                <div>
                  <p className="text-sm font-semibold text-white">By appointment only</p>
                  <p className="text-xs text-muted-foreground mt-0.5">Only open by confirmed booking</p>
                </div>
                {hoursMode === "appointment" && <Check className="w-4 h-4 text-emerald-500" />}
              </button>
            </div>
          </div>
        );

      case 4:
        // Step 4: Add profile picture (7.jpg)
        return (
          <div className="space-y-6 py-4 flex flex-col items-center text-center">
            <div className="w-full text-left">
              <h3 className="text-lg font-bold text-white mb-2">Add a profile picture</h3>
              <p className="text-xs text-muted-foreground">
                A clear image can help build trust and attract potential customers.
              </p>
            </div>

            <div className="relative group cursor-pointer my-6" onClick={handleAvatarClick}>
              <div className="w-28 h-28 rounded-full bg-[#1f2c34] border-4 border-white/5 flex items-center justify-center overflow-hidden shadow-xl">
                {avatarUrl ? (
                  <img src={avatarUrl} alt="Logo preview" className="w-full h-full object-cover" />
                ) : (
                  <Store className="w-12 h-12 text-muted-foreground" />
                )}
              </div>
              <div className="absolute inset-0 flex items-center justify-center bg-black/50 rounded-full opacity-0 group-hover:opacity-100 transition-opacity">
                {uploading ? (
                  <Loader2 className="w-6 h-6 text-white animate-spin" />
                ) : (
                  <Camera className="w-6 h-6 text-white" />
                )}
              </div>
            </div>
            
            <input
              type="file"
              ref={fileInputRef}
              onChange={handleFileChange}
              accept="image/*"
              className="hidden"
            />
            
            <button
              onClick={handleAvatarClick}
              className="text-xs font-semibold text-emerald-500 hover:text-emerald-400 mt-2"
            >
              {avatarUrl ? "Change logo" : "Upload picture"}
            </button>
          </div>
        );

      case 5:
        // Step 5: Add a business description (4.jpg)
        return (
          <div className="space-y-6 py-4">
            <div className="flex justify-between items-start">
              <div>
                <h3 className="text-lg font-bold text-white mb-2">Add a business description</h3>
                <p className="text-xs text-muted-foreground">
                  Tell potential customers what you do and why they should choose you.
                </p>
              </div>
              <button
                onClick={() => setStep(6)}
                className="text-xs font-semibold text-muted-foreground hover:text-white"
              >
                Skip
              </button>
            </div>

            <div className="space-y-2">
              <Textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Add a description"
                className="bg-[#1f2c34] border-white/10 text-white rounded-xl p-4 focus:border-emerald-500 focus:ring-emerald-500/20"
                rows={6}
              />
            </div>
          </div>
        );

      case 6:
        // Step 6: Contact Info (Website, Email, Phone, Address)
        return (
          <div className="space-y-4 py-4 max-h-[350px] overflow-y-auto pr-1">
            <div>
              <h3 className="text-lg font-bold text-white mb-1">Contact Details</h3>
              <p className="text-xs text-muted-foreground">
                Add optional contact details for your business profile.
              </p>
            </div>

            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="website" className="text-xs font-medium text-muted-foreground">
                  Website
                </Label>
                <div className="relative">
                  <span className="absolute left-3 top-3"><Globe className="w-4 h-4 text-muted-foreground" /></span>
                  <Input
                    id="website"
                    value={website}
                    onChange={(e) => setWebsite(e.target.value)}
                    placeholder="https://example.com"
                    className="bg-[#1f2c34] border-white/10 text-white pl-9 rounded-xl focus:border-emerald-500 focus:ring-emerald-500/20"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <Label htmlFor="email" className="text-xs font-medium text-muted-foreground">
                  Email
                </Label>
                <div className="relative">
                  <span className="absolute left-3 top-3"><Mail className="w-4 h-4 text-muted-foreground" /></span>
                  <Input
                    id="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="contact@business.com"
                    type="email"
                    className="bg-[#1f2c34] border-white/10 text-white pl-9 rounded-xl focus:border-emerald-500 focus:ring-emerald-500/20"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <Label htmlFor="phone" className="text-xs font-medium text-muted-foreground">
                  Phone Number
                </Label>
                <div className="relative">
                  <span className="absolute left-3 top-3"><Phone className="w-4 h-4 text-muted-foreground" /></span>
                  <Input
                    id="phone"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="(555) 555-5555"
                    className="bg-[#1f2c34] border-white/10 text-white pl-9 rounded-xl focus:border-emerald-500 focus:ring-emerald-500/20"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <Label htmlFor="address" className="text-xs font-medium text-muted-foreground">
                  Address
                </Label>
                <div className="relative">
                  <span className="absolute left-3 top-3"><MapPin className="w-4 h-4 text-muted-foreground" /></span>
                  <Input
                    id="address"
                    value={address}
                    onChange={(e) => setAddress(e.target.value)}
                    placeholder="123 Market St, City, Country"
                    className="bg-[#1f2c34] border-white/10 text-white pl-9 rounded-xl focus:border-emerald-500 focus:ring-emerald-500/20"
                  />
                </div>
              </div>
            </div>
          </div>
        );

      default:
        return null;
    }
  };

  const getStepPercent = () => {
    return (step / 6) * 100;
  };

  const handleNext = () => {
    if (step < 6) {
      setStep(step + 1);
    } else {
      handleSave();
    }
  };

  const handleBack = () => {
    if (step > 1) {
      setStep(step - 1);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md bg-black border-white/10 text-white rounded-2xl p-6 shadow-2xl">
        <DialogHeader className="border-b border-white/10 pb-3">
          <DialogTitle className="text-base font-bold text-center">
            {step === 1 ? "Create your business profile" : `Step ${step} of 6`}
          </DialogTitle>
        </DialogHeader>

        {fetching ? (
          <div className="py-20 flex flex-col items-center justify-center gap-3">
            <Loader2 className="w-8 h-8 text-emerald-500 animate-spin" />
            <p className="text-xs text-muted-foreground">Fetching business details...</p>
          </div>
        ) : (
          <div className="flex-1 flex flex-col justify-between min-h-[300px]">
            {/* Step Progress Line */}
            {!isEditingHoursDetail && (
              <div className="w-full h-1 bg-[#1f2c34] rounded-full overflow-hidden mt-2">
                <div
                  className="h-full bg-emerald-500 transition-all duration-300"
                  style={{ width: `${getStepPercent()}%` }}
                />
              </div>
            )}

            {/* Render Current Step Form */}
            <div className="flex-1 mt-4">{renderStep()}</div>

            {/* Footer Buttons */}
            {!isEditingHoursDetail && (
              <div className="flex items-center gap-3 mt-6 pt-3 border-t border-white/10">
                {step > 1 && (
                  <Button
                    variant="ghost"
                    onClick={handleBack}
                    className="flex-1 bg-[#1f2c34]/50 border border-white/10 hover:bg-[#1f2c34] text-white hover:text-white rounded-xl"
                  >
                    Back
                  </Button>
                )}
                <Button
                  onClick={handleNext}
                  disabled={loading || uploading}
                  className="flex-grow brand-gradient text-primary-foreground font-semibold rounded-xl py-5"
                >
                  {loading ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Saving...
                    </>
                  ) : step === 6 ? (
                    "Save & Finish"
                  ) : (
                    "Continue"
                  )}
                </Button>
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
};
