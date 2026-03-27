(function () {
    function updateClock() {
        const clockNode = document.getElementById("mfHeaderClock");
        if (!clockNode) {
            return;
        }
        const valueNode = clockNode.querySelector(".mf-header-clock-value");
        const now = new Date();
        const timeText = now.toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
            hour12: true,
        });
        const dateText = now.toLocaleDateString([], {
            weekday: "short",
            day: "2-digit",
            month: "short",
            year: "numeric",
        });
        if (valueNode) {
            valueNode.textContent = timeText;
        }
        clockNode.title = dateText;
    }

    function animateCounters() {
        const counters = document.querySelectorAll(".hc-animate-value[data-count]");
        counters.forEach((counter) => {
            const targetValue = Number(counter.dataset.count || 0);
            if (!Number.isFinite(targetValue)) {
                return;
            }
            const startTime = performance.now();
            const duration = 900;

            function drawFrame(now) {
                const progress = Math.min((now - startTime) / duration, 1);
                const eased = 1 - Math.pow(1 - progress, 3);
                counter.textContent = Math.round(targetValue * eased).toLocaleString("en-IN");
                if (progress < 1) {
                    window.requestAnimationFrame(drawFrame);
                }
            }

            window.requestAnimationFrame(drawFrame);
        });
    }

    function bindLeadFilters() {
        const chips = document.querySelectorAll(".hc-filter-chip");
        const rows = document.querySelectorAll("#leadTableBody tr");
        const searchInput = document.getElementById("leadSearchInput");

        function render() {
            const activeChip = document.querySelector(".hc-filter-chip.is-active");
            const filter = activeChip?.dataset.filterStatus || "all";
            const query = (searchInput?.value || "").trim().toLowerCase();

            rows.forEach((row) => {
                const rowText = row.textContent.toLowerCase();
                const matchesStatus = filter === "all" || row.dataset.status === filter;
                const matchesQuery = !query || rowText.includes(query);
                row.hidden = !(matchesStatus && matchesQuery);
            });
        }

        chips.forEach((chip) => {
            chip.addEventListener("click", () => {
                chips.forEach((item) => item.classList.remove("is-active"));
                chip.classList.add("is-active");
                render();
            });
        });

        searchInput?.addEventListener("input", render);
        render();
    }

    function bindSectionSpy() {
        const links = Array.from(document.querySelectorAll(".hc-nav-link"));
        const sections = links
            .map((link) => document.querySelector(link.getAttribute("href")))
            .filter(Boolean);

        if (!links.length || !sections.length || !("IntersectionObserver" in window)) {
            return;
        }

        const observer = new IntersectionObserver((entries) => {
            const visible = entries
                .filter((entry) => entry.isIntersecting)
                .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
            if (!visible) {
                return;
            }
            links.forEach((link) => {
                link.classList.toggle("active", link.getAttribute("href") === `#${visible.target.id}`);
            });
        }, {
            threshold: 0.32,
            rootMargin: "-15% 0px -55% 0px",
        });

        sections.forEach((section) => observer.observe(section));
    }

    function readPayload() {
        const node = document.getElementById("heavenectionDashboardPayload");
        if (!node) {
            return null;
        }
        try {
            return JSON.parse(node.textContent);
        } catch (error) {
            return null;
        }
    }

    function renderCharts() {
        const payload = readPayload();
        if (typeof Chart === "undefined" || !payload) {
            return;
        }
        const gridColor = "rgba(77, 92, 144, 0.16)";
        const textColor = "#334155";
        const surface = "#ffffff";
        const leadPipelineChart = document.getElementById("leadPipelineChart");
        const callVolumeChart = document.getElementById("callVolumeChart");
        const activityBalanceChart = document.getElementById("activityBalanceChart");

        if (!leadPipelineChart || !callVolumeChart || !activityBalanceChart) {
            return;
        }

        new Chart(leadPipelineChart, {
            type: "doughnut",
            data: {
                labels: payload.leadPipeline.labels,
                datasets: [{
                    data: payload.leadPipeline.values,
                    backgroundColor: ["#4d5c90", "#6f80ba", "#f0a53a", "#a9b2cf", "#2d9d68"],
                    borderColor: surface,
                    borderWidth: 4,
                }],
            },
            options: {
                plugins: { legend: { position: "bottom", labels: { color: textColor } } },
                cutout: "64%",
            },
        });

        new Chart(callVolumeChart, {
            type: "line",
            data: {
                labels: payload.callVolume.labels,
                datasets: [
                    {
                        label: "Calls",
                        data: payload.callVolume.calls,
                        borderColor: "#4d5c90",
                        backgroundColor: "rgba(77, 92, 144, 0.18)",
                        fill: true,
                        tension: 0.28,
                    },
                    {
                        label: "Conversions",
                        data: payload.callVolume.conversions,
                        borderColor: "#6f80ba",
                        backgroundColor: "rgba(111, 128, 186, 0.12)",
                        fill: true,
                        tension: 0.28,
                    },
                ],
            },
            options: {
                plugins: { legend: { labels: { color: textColor } } },
                scales: {
                    y: { beginAtZero: true, grid: { color: gridColor }, ticks: { color: textColor } },
                    x: { grid: { display: false }, ticks: { color: textColor } },
                },
            },
        });

        new Chart(activityBalanceChart, {
            type: "bar",
            data: {
                labels: payload.activityBalance.labels,
                datasets: [
                    {
                        label: "Active Hours",
                        data: payload.activityBalance.activeHours,
                        backgroundColor: "#4d5c90",
                        borderRadius: 8,
                    },
                    {
                        label: "Call Minutes",
                        data: payload.activityBalance.callMinutes,
                        backgroundColor: "#8d9dcf",
                        borderRadius: 8,
                    },
                ],
            },
            options: {
                plugins: { legend: { labels: { color: textColor } } },
                scales: {
                    y: { beginAtZero: true, grid: { color: gridColor }, ticks: { color: textColor } },
                    x: { grid: { display: false }, ticks: { color: textColor } },
                },
            },
        });
    }

    function bindAddStaffForm() {
        const config = window.heavenectionAdmin;
        const form = document.getElementById("addStaffForm");
        const feedback = document.getElementById("addStaffFeedback");
        const submitButton = document.getElementById("addStaffSubmitButton");
        const modalNode = document.getElementById("addStaffModal");

        if (!config?.createStaffUrl || !form || !feedback || !submitButton || !modalNode) {
            return;
        }

        function setFeedback(message, isError) {
            feedback.textContent = message;
            feedback.classList.remove("d-none", "is-success", "is-error");
            feedback.classList.add(isError ? "is-error" : "is-success");
        }

        function clearFeedback() {
            feedback.textContent = "";
            feedback.classList.add("d-none");
            feedback.classList.remove("is-success", "is-error");
        }

        function extractErrorMessage(payload) {
            if (!payload || typeof payload !== "object") {
                return "Unable to create staff right now.";
            }
            if (payload.detail) {
                return String(payload.detail);
            }

            const firstKey = Object.keys(payload)[0];
            if (!firstKey) {
                return "Unable to create staff right now.";
            }

            const value = payload[firstKey];
            if (Array.isArray(value) && value.length) {
                return String(value[0]);
            }
            return String(value);
        }

        modalNode.addEventListener("hidden.bs.modal", clearFeedback);

        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            clearFeedback();
            submitButton.disabled = true;

            const formData = new FormData(form);
            const payload = {
                name: String(formData.get("name") || "").trim(),
                phone: String(formData.get("phone") || "").trim(),
                password: String(formData.get("password") || ""),
                hourly_rate: String(formData.get("hourly_rate") || "150"),
                call_rate: String(formData.get("call_rate") || "3"),
                bonus_per_conversion: String(formData.get("bonus_per_conversion") || "500"),
                is_active: formData.get("is_active") === "true",
            };

            try {
                const response = await fetch(config.createStaffUrl, {
                    method: "POST",
                    credentials: "same-origin",
                    headers: {
                        "Content-Type": "application/json",
                        "Accept": "application/json",
                    },
                    body: JSON.stringify(payload),
                });

                let responsePayload = null;
                try {
                    responsePayload = await response.json();
                } catch (error) {
                    responsePayload = null;
                }

                if (!response.ok) {
                    setFeedback(extractErrorMessage(responsePayload), true);
                    return;
                }

                setFeedback("Staff member created successfully.", false);
                form.reset();
                const modal = bootstrap.Modal.getOrCreateInstance(modalNode);
                window.setTimeout(() => {
                    modal.hide();
                    window.location.reload();
                }, 700);
            } catch (error) {
                setFeedback("Network issue while creating staff.", true);
            } finally {
                submitButton.disabled = false;
            }
        });
    }

    if (typeof initMateriallyLayout === "function") {
        initMateriallyLayout();
    }
    if (typeof initDashboardUX === "function") {
        initDashboardUX();
    }

    updateClock();
    window.setInterval(updateClock, 1000);
    animateCounters();
    bindLeadFilters();
    bindSectionSpy();
    renderCharts();
    bindAddStaffForm();
})();
