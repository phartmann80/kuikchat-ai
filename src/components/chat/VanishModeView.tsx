import { EyeOff, Shield, Clock, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { useState } from "react";

export const VanishModeView = () => {
  const [vanishEnabled, setVanishEnabled] = useState(false);

  return (
    <div className="flex-1 flex flex-col bg-card">
      <div className="p-4 border-b border-border">
        <h2 className="text-xl font-semibold">Vanish Mode</h2>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center p-6">
        <div className={`w-32 h-32 rounded-full flex items-center justify-center mb-6 transition-all duration-300 ${
          vanishEnabled ? 'bg-primary/20 shadow-lg shadow-primary/20' : 'bg-muted/50'
        }`}>
          <EyeOff className={`w-16 h-16 transition-colors ${vanishEnabled ? 'text-primary' : 'text-muted-foreground'}`} />
        </div>

        <h3 className="text-2xl font-bold mb-2">
          {vanishEnabled ? 'Vanish Mode Active' : 'Vanish Mode'}
        </h3>
        <p className="text-muted-foreground text-center mb-8 max-w-sm">
          {vanishEnabled 
            ? 'Your messages will disappear after they are seen'
            : 'Enable vanish mode to send messages that disappear after being viewed'
          }
        </p>

        <div className="flex items-center gap-4 mb-8">
          <span className="text-sm text-muted-foreground">Off</span>
          <Switch 
            checked={vanishEnabled} 
            onCheckedChange={setVanishEnabled}
            className="data-[state=checked]:bg-primary"
          />
          <span className="text-sm text-muted-foreground">On</span>
        </div>

        <div className="w-full max-w-sm space-y-4">
          <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/30">
            <Shield className="w-5 h-5 text-primary mt-0.5" />
            <div>
              <p className="font-medium text-sm">Member-only access</p>
              <p className="text-xs text-muted-foreground">Only conversation members can read these messages in-app</p>
            </div>
          </div>

          <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/30">
            <Clock className="w-5 h-5 text-primary mt-0.5" />
            <div>
              <p className="font-medium text-sm">Auto-delete after viewing</p>
              <p className="text-xs text-muted-foreground">Messages vanish once seen</p>
            </div>
          </div>

          <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/30">
            <Sparkles className="w-5 h-5 text-primary mt-0.5" />
            <div>
              <p className="font-medium text-sm">Screenshot alerts</p>
              <p className="text-xs text-muted-foreground">Get notified if someone takes a screenshot</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
