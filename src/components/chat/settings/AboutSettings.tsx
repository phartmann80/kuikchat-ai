import { ChevronLeft, Info, Shield, FileText, Heart, ExternalLink, Github } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useNavigate } from "react-router-dom";
import kuikchatLogo from "@/assets/kuikchat-logo.png";

interface AboutSettingsProps {
  onBack: () => void;
}

const legalLinks = [
  { icon: FileText, label: "Terms of Service", path: "/#privacy" },
  { icon: Shield, label: "Privacy Policy", path: "/#privacy" },
  { icon: FileText, label: "Licenses", path: "/#about" },
];

const socialLinks = [
  { icon: () => <svg viewBox="0 0 24 24" className="w-5 h-5 fill-current text-muted-foreground"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>, label: "X", href: "#" },
  { icon: Github, label: "GitHub", href: "#" },
];

export const AboutSettings = ({ onBack }: AboutSettingsProps) => {
  const navigate = useNavigate();

  const handleLegalClick = (path: string) => {
    navigate(path);
  };

  return (
    <div className="flex-1 flex flex-col bg-card">
      <div className="p-4 border-b border-border flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={onBack} className="rounded-full">
          <ChevronLeft className="w-5 h-5" />
        </Button>
        <h2 className="text-xl font-semibold">About</h2>
      </div>

      <ScrollArea className="flex-1">
        <div className="p-4 space-y-6">
          {/* App Info */}
          <div className="text-center py-6">
            <div className="w-24 h-24 mx-auto mb-4 rounded-2xl bg-gradient-to-b from-primary/20 to-primary/5 flex items-center justify-center overflow-hidden">
              <img src={kuikchatLogo} alt="KuikChat" className="w-16 h-16 object-contain" />
            </div>
            <h3 className="text-2xl font-bold">KuikChat</h3>
            <p className="text-muted-foreground">Version 1.0.0</p>
            <p className="text-sm text-muted-foreground mt-2">
              Your AI-Powered Communication Platform
            </p>
          </div>

          {/* Features */}
          <div className="p-4 rounded-xl bg-gradient-to-r from-primary/10 to-secondary/10 border border-border/50">
            <h4 className="font-medium mb-3">What's new in this version</h4>
            <ul className="space-y-2 text-sm text-muted-foreground">
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                Authenticated messaging with member-only access controls
              </li>
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                AI-powered translation and assistant
              </li>
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                Voice and video calling with HD quality
              </li>
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                Custom avatars and stickers
              </li>
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                Disappearing messages and privacy features
              </li>
            </ul>
          </div>

          {/* Legal */}
          <div className="space-y-2">
            {legalLinks.map((link) => (
              <button 
                key={link.label}
                onClick={() => handleLegalClick(link.path)}
                className="w-full flex items-center justify-between p-3 rounded-lg hover:bg-muted/30 cursor-pointer transition-colors text-left"
              >
                <div className="flex items-center gap-3">
                  <link.icon className="w-5 h-5 text-muted-foreground" />
                  <p className="font-medium">{link.label}</p>
                </div>
                <ExternalLink className="w-4 h-4 text-muted-foreground" />
              </button>
            ))}
          </div>

          {/* Social Links */}
          <div className="space-y-2">
            <h4 className="font-medium text-sm text-muted-foreground px-1">Follow us</h4>
            {socialLinks.map((link) => (
              <a 
                key={link.label}
                href={link.href}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center justify-between p-3 rounded-lg hover:bg-muted/30 cursor-pointer transition-colors"
              >
                <div className="flex items-center gap-3">
                  <link.icon />
                  <p className="font-medium">{link.label}</p>
                </div>
                <ExternalLink className="w-4 h-4 text-muted-foreground" />
              </a>
            ))}
          </div>

          {/* Footer */}
          <div className="text-center py-6 space-y-2">
            <p className="text-sm text-muted-foreground">
              Made with <Heart className="w-4 h-4 inline text-red-500" /> by HEFTCoder Labs
            </p>
            <p className="text-xs text-muted-foreground">
              © 2024 KuikChat. All rights reserved.
            </p>
          </div>
        </div>
      </ScrollArea>
    </div>
  );
};
