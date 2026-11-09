// Linux 验证程序：确认 RimeBridgeC 的部署、组合、候选、选词、翻页与退格链路。
// 不参与 iOS 构建；由 ios/scripts/verify-rime-linux.sh 调用。
#include "RimeBridgeC.h"

#include <cstdio>
#include <cstring>
#include <string>

namespace {

void print_result(const char *tag, char *json) {
    std::printf("%s: %s\n", tag, json ? json : "(null)");
    xime_rime_free_string(json);
}

void type_key(xime_rime_session *session, int keycode) {
    char text[2] = {static_cast<char>(keycode), '\0'};
    print_result(text, xime_rime_process_key(session, keycode, 0));
}

void type_text(xime_rime_session *session, const char *text) {
    for (const char *p = text; *p; ++p) {
        type_key(session, static_cast<unsigned char>(*p));
    }
}

}  // namespace

int main(int argc, char **argv) {
    const char *shared = argc > 1 ? argv[1] : nullptr;
    const char *user = argc > 2 ? argv[2] : nullptr;
    const char *schema = argc > 3 ? argv[3] : "pinyin_simp";

    if (!shared || !user) {
        std::fprintf(stderr, "usage: %s <shared_data_dir> <user_data_dir> [schema]\n",
                     argv[0]);
        return 64;
    }

    if (!xime_rime_deploy(shared, user, true)) {
        std::fprintf(stderr, "deploy failed\n");
        return 1;
    }
    std::printf("deploy ok\n");

    xime_rime_session *session = xime_rime_create(shared, user);
    if (!session) {
        std::fprintf(stderr, "create failed\n");
        return 2;
    }

    print_result("schema", xime_rime_select_schema(session, schema));

    // 逐键组合 + 选择候选。
    type_text(session, "nihao");
    print_result("select 0", xime_rime_select_candidate(session, 0));
    print_result("status", xime_rime_status(session));

    // 空格选首候选。
    type_text(session, "nihao");
    print_result("space", xime_rime_process_key(session, 0x20, 0));

    // 退格删组合。
    type_text(session, "ni");
    print_result("backspace", xime_rime_delete_backward(session));

    // 翻页：清空后只输入 a，候选应有多页。
    xime_rime_reset(session);
    type_key(session, 'a');
    print_result("page down", xime_rime_change_page(session, false));
    print_result("page up", xime_rime_change_page(session, true));

    xime_rime_destroy(session);
    return 0;
}
