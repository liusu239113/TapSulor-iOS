/// 在 TapTap 页面里执行的只读脚本（不修改页面）。
enum PageScripts {
    /// 登录窗口中使用页面自己的会话读取开发者 ID（对齐桌面版 jsCheck）。
    static let developerIdFromSession = #"""
    const norm = (value) => {
      if (value == null) return null;
      const text = String(value).trim();
      if (/^\d+$/.test(text)) return text;
      if (text.endsWith(".0") && /^\d+$/.test(text.slice(0, -2))) return text.slice(0, -2);
      return null;
    };
    try {
      const me = await fetch("/api/user/v1/me", { credentials: "include" });
      if (me.status === 401 || me.status === 403) return null;
      const meJson = await me.json();
      const data = meJson && meJson.data;
      const fromMe = data ? (norm(data.developer_id) || norm(data.developerId) || (data.developer && norm(data.developer.id))) : null;
      if (fromMe) return fromMe;
      const list = await fetch("/api/developer/v1/list", { credentials: "include" });
      if (!list.ok) return null;
      const listJson = await list.json();
      const items = listJson && listJson.data && Array.isArray(listJson.data.list) ? listJson.data.list : [];
      for (const item of items) {
        const id = norm(item.developer_id) || norm(item.developerId) || norm(item.id);
        if (id) return id;
      }
      return null;
    } catch (error) {
      return null;
    }
    """#
}
