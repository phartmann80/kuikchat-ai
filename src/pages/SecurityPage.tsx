import { StaticLayout } from "@/components/layout/StaticLayout";
import { Privacy } from "@/components/landing/Privacy";

const SecurityPage = () => {
    return (
        <StaticLayout
            title="Security & Privacy"
            subtitle="Your data is your business. We protect accounts with authentication and access controls."
        >
            <Privacy />
            <div className="mt-12 space-y-6">
                <h3 className="text-2xl font-bold">Privacy-First Architecture</h3>
                <p className="text-muted-foreground">
                    At KuikChat, we don't just add security as an afterthought. Our entire platform is built on a zero-trust architecture, ensuring that your messages, files, and calls are always protected.
                </p>
            </div>
        </StaticLayout>
    );
};

export default SecurityPage;
