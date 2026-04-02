(function () {
    const config = window.heavenectionNetwork || {};
    const offlinePath = config.offlinePath || "/offline/";
    const storageKey = "heavenectionLastPage";
    const overlay = document.getElementById("heavenectionNetworkOverlay");
    const messageNode = document.getElementById("heavenectionNetworkMessage");
    const retryButton = document.getElementById("heavenectionNetworkRetry");

    function currentPath() {
        return window.location.pathname + window.location.search + window.location.hash;
    }

    function rememberLastPage() {
        if (window.location.pathname === offlinePath) {
            return;
        }
        window.localStorage.setItem(storageKey, currentPath());
    }

    function lastPage() {
        return window.localStorage.getItem(storageKey) || "/";
    }

    function showOverlay(message) {
        if (overlay) {
            overlay.hidden = false;
            document.body.classList.add("hc-network-open");
        }
        if (messageNode && message) {
            messageNode.textContent = message;
        }
    }

    function hideOverlay() {
        if (overlay) {
            overlay.hidden = true;
            document.body.classList.remove("hc-network-open");
        }
    }

    function restoreLastPage() {
        const targetPath = lastPage();
        if (window.location.pathname === offlinePath) {
            window.location.replace(targetPath);
            return;
        }
        hideOverlay();
    }

    window.heavenectionNetworkState = {
        show(message) {
            showOverlay(
                message ||
                    "Connection interrupted. Please wait while the page reconnects.",
            );
        },
        hide: hideOverlay,
        restore: restoreLastPage,
    };

    retryButton?.addEventListener("click", () => {
        if (window.navigator.onLine) {
            restoreLastPage();
            return;
        }
        showOverlay("Still offline. Please check your internet connection and try again.");
    });

    window.addEventListener("offline", () => {
        showOverlay(
            "Connection interrupted. Please check your internet connection.",
        );
    });

    window.addEventListener("online", () => {
        restoreLastPage();
    });

    rememberLastPage();

    if (window.location.pathname === offlinePath && window.navigator.onLine) {
        window.setTimeout(restoreLastPage, 500);
    } else if (!window.navigator.onLine) {
        showOverlay(
            "Connection interrupted. Please check your internet connection.",
        );
    }
})();
