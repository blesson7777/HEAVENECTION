(() => {
    const config = window.tripMateAdminPwa;
    if (!config) {
        return;
    }

    const installButton = document.getElementById("adminInstallAppButton");
    let deferredPrompt = null;

    const isStandalone = () =>
        window.matchMedia("(display-mode: standalone)").matches
        || window.navigator.standalone === true;

    const setInstallButtonVisible = (isVisible) => {
        if (!installButton) {
            return;
        }
        installButton.classList.toggle("d-none", !isVisible || isStandalone());
    };

    if ("serviceWorker" in navigator) {
        window.addEventListener("load", () => {
            navigator.serviceWorker.register(config.serviceWorkerUrl, {
                scope: config.serviceWorkerScope,
            }).catch(() => {
                setInstallButtonVisible(false);
            });
        });
    }

    window.addEventListener("beforeinstallprompt", (event) => {
        event.preventDefault();
        deferredPrompt = event;
        setInstallButtonVisible(true);
    });

    window.addEventListener("appinstalled", () => {
        deferredPrompt = null;
        setInstallButtonVisible(false);
    });

    installButton?.addEventListener("click", async () => {
        if (deferredPrompt) {
            deferredPrompt.prompt();
            await deferredPrompt.userChoice;
            deferredPrompt = null;
            setInstallButtonVisible(false);
            return;
        }

        const isIosDevice = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
        if (isIosDevice) {
            window.alert("Use Safari Share > Add to Home Screen to install HEAVENECTION Admin.");
            return;
        }

        window.alert("Use your browser install menu to install HEAVENECTION Admin.");
    });

    setInstallButtonVisible(false);
})();
