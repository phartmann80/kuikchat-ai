import { StaticLayout } from "@/components/layout/StaticLayout";
import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";

const PricingPage = () => {
    const plans = [
        {
            name: "Personal",
            price: "$0",
            description: "Perfect for individuals and small groups.",
            features: ["Secure account access", "AI Assistant (Limited)", "3 Devices Sync", "5GB Cloud Storage"],
            cta: "Get Started",
            highlight: false
        },
        {
            name: "Pro",
            price: "$9.99/mo",
            description: "Advanced features for power users.",
            features: ["Unlimited AI Assistant", "Unlimited Devices", "50GB Cloud Storage", "Priority Support", "Custom Wallpapers"],
            cta: "Start Free Trial",
            highlight: true
        }
    ];

    return (
        <StaticLayout
            title="Simple Pricing"
            subtitle="KuikChat is currently in beta. All features are free for early adopters."
        >
            <div className="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
                {plans.map((plan, i) => (
                    <div key={i} className={`p-8 rounded-3xl border ${plan.highlight ? 'border-primary ring-1 ring-primary' : 'border-border'} flex flex-col`}>
                        <h3 className="text-2xl font-bold mb-2">{plan.name}</h3>
                        <div className="flex items-baseline gap-1 mb-4">
                            <span className="text-4xl font-bold">{plan.price}</span>
                        </div>
                        <p className="text-muted-foreground mb-6">{plan.description}</p>
                        <ul className="space-y-4 mb-8 flex-1">
                            {plan.features.map((f, j) => (
                                <li key={j} className="flex items-center gap-2 text-sm">
                                    <Check className="w-4 h-4 text-primary" />
                                    {f}
                                </li>
                            ))}
                        </ul>
                        <Button variant={plan.highlight ? "brand" : "outline"} className="w-full h-12">
                            {plan.cta}
                        </Button>
                    </div>
                ))}
            </div>
            <p className="text-center mt-12 text-sm text-muted-foreground italic">
                * Pricing plans are subject to change after the Beta period.
            </p>
        </StaticLayout>
    );
};

export default PricingPage;
