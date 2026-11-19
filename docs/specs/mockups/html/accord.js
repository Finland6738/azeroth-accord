// Azeroth Accord mockups: page behaviour. Only one thing: "?clean" in the address hides the callouts and the legend,
// which is how docs/specs/mockups/render.sh makes the clean copy of each annotated mockup (img/clean/).
(function () {
  if (/[?&]clean\b/.test(location.search)) document.documentElement.className += " clean-root";
  document.addEventListener("DOMContentLoaded", function () {
    if (/[?&]clean\b/.test(location.search)) document.body.className += " clean";
  });
})();
