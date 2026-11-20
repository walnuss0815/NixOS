import { Plugin } from "@opencode/plugin/tui"

// Replaces OpenCode's built-in terminal title (terminal.title = false) to
// prefix "● " while the session or one of its subagents is running.
export default Plugin.define({
  id: "local.title",
  setup(context) {
    const { data, ui, renderer } = context
    let last = ""
    const compute = () => {
      const route = ui.router.current()
      if (route?.type === "plugin") return `OC | ${route.name}`
      if (route?.type !== "session") return "OpenCode"
      const title = data.session.get(route.sessionID)?.title
      if (!title || /^(New|Child) session - \d{4}-/.test(title)) return "OpenCode"
      const busy = [route.sessionID, ...data.session.family(route.sessionID)].some(
        (id) => data.session.status(id) === "running",
      )
      return `${busy ? "● " : ""}OC | ${title.length > 40 ? title.slice(0, 37) + "\u2026" : title}`
    }
    // shortcut: polls twice a second instead of tracking route and status
    // changes reactively; switch if the plugin API grows a route event.
    const timer = setInterval(() => {
      const next = compute()
      if (next === last) return
      last = next
      renderer.setTerminalTitle(next)
    }, 500)
    return () => clearInterval(timer)
  },
})
