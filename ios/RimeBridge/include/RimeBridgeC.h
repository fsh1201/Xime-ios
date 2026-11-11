#ifndef XIME_RIME_BRIDGE_C_H
#define XIME_RIME_BRIDGE_C_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 初始化 librime 并执行部署（构建词典/schema）。
/// full_check 为 true 时做全量检查，首次安装应使用 true；
/// 键盘扩展里建议只做 false 的增量维护，避免阻塞。
/// 成功返回 true。
bool xime_rime_deploy(const char *shared_data_dir,
                      const char *user_data_dir,
                      bool full_check);

/// 不透明会话句柄。
typedef struct xime_rime_session xime_rime_session;

/// 初始化 librime 并创建会话。
/// shared_data_dir 存放 schema/词典，user_data_dir 存放用户词典。
/// 失败返回 NULL。
xime_rime_session *xime_rime_create(const char *shared_data_dir,
                                    const char *user_data_dir);

/// 与 xime_rime_create 相同，但不执行维护/部署。
/// 用于已经内置预编译词典、且运行在键盘扩展里的场景。
xime_rime_session *xime_rime_create_passive(const char *shared_data_dir,
                                            const char *user_data_dir);

void xime_rime_destroy(xime_rime_session *session);
void xime_rime_reset(xime_rime_session *session);

/// 以下函数返回 UTF-8 JSON 字符串，调用方必须用 xime_rime_free_string 释放。
/// JSON 结构：
/// {
///   "commit": "提交文本（可能为空）",
///   "preedit": "组合文本",
///   "candidates": [{"text": "候选", "comment": "注释或 null"}],
///   "pageNo": 0,
///   "isLastPage": true,
///   "asciiMode": false
/// }
char *xime_rime_process_key(xime_rime_session *session, int keycode, int modifiers);
/// 只处理按键，返回 commit/preedit，不生成候选（JSON 中 "stale": true）。
/// 用于快速输入，候选由 xime_rime_context 在停顿后刷新。
char *xime_rime_process_key_fast(xime_rime_session *session, int keycode, int modifiers);
/// 获取当前上下文（会生成候选）。
char *xime_rime_context(xime_rime_session *session);
char *xime_rime_select_candidate(xime_rime_session *session, int index);
char *xime_rime_select_schema(xime_rime_session *session, const char *schema_id);
/// backward 为 true 时翻到上一页，false 时翻到下一页。
char *xime_rime_change_page(xime_rime_session *session, bool backward);
char *xime_rime_commit(xime_rime_session *session);
char *xime_rime_delete_backward(xime_rime_session *session);
char *xime_rime_set_option(xime_rime_session *session, const char *name, bool value);
char *xime_rime_status(xime_rime_session *session);

void xime_rime_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
