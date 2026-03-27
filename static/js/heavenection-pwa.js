(function () {
    const config = window.heavenectionPwa;
    const installButton = document.getElementById("heavenectionInstallButton");
    let deferredPrompt = null;
    const legacyHashRoutes = {
        "#dashboard": "/",
        "#staff": "/staff/",
        "#team": "/staff/",
        "#leads": "/leads/",
        "#calls": "/calls/",
        "#call-details": "/calls/",
        "#reports": "/working-hours/",
        "#working-hours": "/working-hours/",
    };

    function redirectLegacyHashRoute() {
        const hash = (window.location.hash || "").toLowerCase();
        const targetPath = legacyHashRoutes[hash];
        if (!targetPath) {
            return;
        }

        const targetUrl = new URL(targetPath, window.location.origin);
        if (targetUrl.pathname === window.location.pathname) {
            window.history.replaceState(null, "", targetUrl.pathname + targetUrl.search);
            return;
        }

        window.location.replace(targetUrl.pathname + targetUrl.search);
    }

    function isStandalone() {
        return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
    }

    function toggleInstallButton(visible) {
        if (!installButton) {
            return;
        }
        installButton.classList.toggle("d-none", !visible || isStandalone());
    }

    if (config?.serviceWorkerUrl && "serviceWorker" in navigator) {
        window.addEventListener("load", () => {
            navigator.serviceWorker
                .register(config.serviceWorkerUrl, { updateViaCache: "none" })
                .then((registration) => registration.update())
                .catch(() => {
                    toggleInstallButton(false);
                });
        });
    }

    window.addEventListener("beforeinstallprompt", (event) => {
        event.preventDefault();
        deferredPrompt = event;
        toggleInstallButton(true);
    });

    window.addEventListener("appinstalled", () => {
        deferredPrompt = null;
        toggleInstallButton(false);
    });

    installButton?.addEventListener("click", async () => {
        if (deferredPrompt) {
            deferredPrompt.prompt();
            await deferredPrompt.userChoice;
            deferredPrompt = null;
            toggleInstallButton(false);
            return;
        }

        const isIosDevice = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
        if (isIosDevice) {
            window.alert("Use Safari Share > Add to Home Screen to install Heavenection CallTrack.");
            return;
        }

        window.alert("Use your browser install menu to install Heavenection CallTrack.");
    });

    toggleInstallButton(false);
    redirectLegacyHashRoute();
})();
