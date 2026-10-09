document.addEventListener("DOMContentLoaded", function () {
    var sidebar = document.getElementById("sidebar");
    var scrim = document.getElementById("scrim");
    var menuBtn = document.getElementById("menuBtn");

    function setOpen(open) {
        if (!sidebar || !scrim) return;
        sidebar.classList.toggle("open", open);
        scrim.classList.toggle("open", open);
    }

    if (menuBtn) {
        menuBtn.addEventListener("click", function () {
            setOpen(!sidebar.classList.contains("open"));
        });
    }

    if (scrim) {
        scrim.addEventListener("click", function () {
            setOpen(false);
        });
    }

    document.querySelectorAll(".btn-zivoc").forEach(function (btn) {
        btn.addEventListener("click", function () {
            btn.classList.add("loading");
        });
    });
});
