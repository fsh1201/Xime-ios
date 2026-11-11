#include "RimeBridgeC.h"

#include <rime_api.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <sstream>
#include <string>

struct xime_rime_session {
    RimeSessionId id = 0;
    RimeApi *api = nullptr;
};

namespace {

std::once_flag g_initialize_once;
bool g_initialized = false;

bool initialize_rime(const char *shared_data_dir, const char *user_data_dir) {
    std::call_once(g_initialize_once, [shared_data_dir, user_data_dir]() {
        RimeApi *api = rime_get_api();
        if (!api) {
            return;
        }

        RimeTraits traits = {0};
        RIME_STRUCT_INIT(RimeTraits, traits);
        traits.shared_data_dir = shared_data_dir;
        traits.user_data_dir = user_data_dir;
        traits.distribution_name = "Xime";
        traits.distribution_code_name = "xime";
        traits.distribution_version = "0.1.0";
        traits.app_name = "Xime";

        api->setup(&traits);
        api->initialize(&traits);
        g_initialized = true;
    });
    return g_initialized;
}

bool start_maintenance(bool full_check) {
    RimeApi *api = rime_get_api();
    if (!api) {
        return false;
    }
    api->start_maintenance(full_check ? 1 : 0);
    api->join_maintenance_thread();
    return true;
}

xime_rime_session *create_session_internal() {
    RimeApi *api = rime_get_api();
    if (!api) {
        return nullptr;
    }

    const RimeSessionId id = api->create_session();
    if (id == 0) {
        return nullptr;
    }

    auto *session = new (std::nothrow) xime_rime_session;
    if (!session) {
        api->destroy_session(id);
        return nullptr;
    }

    session->id = id;
    session->api = api;
    return session;
}

void append_json_string(std::ostringstream &out, const char *value) {
    if (!value) {
        out << "null";
        return;
    }

    out << '"';
    for (const auto *p = reinterpret_cast<const unsigned char *>(value); *p; ++p) {
        switch (*p) {
        case '"':
            out << "\\\"";
            break;
        case '\\':
            out << "\\\\";
            break;
        case '\n':
            out << "\\n";
            break;
        case '\r':
            out << "\\r";
            break;
        case '\t':
            out << "\\t";
            break;
        default:
            if (*p < 0x20) {
                char buffer[8];
                std::snprintf(buffer, sizeof(buffer), "\\u%04x", *p);
                out << buffer;
            } else {
                out << static_cast<char>(*p);
            }
            break;
        }
    }
    out << '"';
}

char *duplicate_string(const std::string &value) {
    auto *result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result) {
        std::memcpy(result, value.c_str(), value.size() + 1);
    }
    return result;
}

char *build_result(xime_rime_session *session) {
    if (!session || !session->api) {
        return nullptr;
    }

    std::ostringstream out;
    out << '{';

    std::string commit_text;
    RimeCommit commit = {0};
    RIME_STRUCT_INIT(RimeCommit, commit);
    if (session->api->get_commit(session->id, &commit)) {
        if (commit.text) {
            commit_text = commit.text;
        }
        session->api->free_commit(&commit);
    }

    out << "\"commit\":";
    append_json_string(out, commit_text.empty() ? nullptr : commit_text.c_str());

    RimeContext context = {0};
    RIME_STRUCT_INIT(RimeContext, context);
    const bool has_context = session->api->get_context(session->id, &context);

    out << ",\"preedit\":";
    append_json_string(out, (has_context && context.composition.preedit)
                                ? context.composition.preedit
                                : "");

    out << ",\"candidates\":[";
    if (has_context) {
        for (int i = 0; i < context.menu.num_candidates; ++i) {
            if (i > 0) {
                out << ',';
            }
            out << "{\"text\":";
            append_json_string(out, context.menu.candidates[i].text);
            out << ",\"comment\":";
            append_json_string(out, context.menu.candidates[i].comment);
            out << '}';
        }
    }
    out << ']';

    out << ",\"pageNo\":" << (has_context ? context.menu.page_no : 0);
    out << ",\"isLastPage\":"
        << ((!has_context || context.menu.is_last_page) ? "true" : "false");

    RimeStatus status = {0};
    RIME_STRUCT_INIT(RimeStatus, status);
    const bool has_status = session->api->get_status(session->id, &status);
    out << ",\"asciiMode\":"
        << ((has_status && status.is_ascii_mode) ? "true" : "false");
    out << ",\"stale\":false";
    if (has_status) {
        session->api->free_status(&status);
    }

    out << '}';

    if (has_context) {
        session->api->free_context(&context);
    }

    return duplicate_string(out.str());
}

char *build_fast_result(xime_rime_session *session) {
    if (!session || !session->api) {
        return nullptr;
    }

    std::ostringstream out;
    out << '{';

    std::string commit_text;
    RimeCommit commit = {0};
    RIME_STRUCT_INIT(RimeCommit, commit);
    if (session->api->get_commit(session->id, &commit)) {
        if (commit.text) {
            commit_text = commit.text;
        }
        session->api->free_commit(&commit);
    }

    out << "\"commit\":";
    append_json_string(out, commit_text.empty() ? nullptr : commit_text.c_str());

    // input 由 Swift 侧本地跟踪；这里不生成候选，也不读取 composition。
    out << ",\"preedit\":\"\"";
    out << ",\"candidates\":[],\"pageNo\":0,\"isLastPage\":true"
           ",\"asciiMode\":false,\"stale\":true}";

    return duplicate_string(out.str());
}

}  // namespace

extern "C" bool xime_rime_deploy(const char *shared_data_dir,
                                 const char *user_data_dir,
                                 bool full_check) {
    if (!shared_data_dir || !user_data_dir) {
        return false;
    }
    if (!initialize_rime(shared_data_dir, user_data_dir)) {
        return false;
    }
    return start_maintenance(full_check);
}

extern "C" xime_rime_session *xime_rime_create(const char *shared_data_dir,
                                                const char *user_data_dir) {
    if (!shared_data_dir || !user_data_dir) {
        return nullptr;
    }
    // 首次部署由主 App 调用 xime_rime_deploy(true) 完成；
    // 键盘扩展这里只做增量维护。
    if (!xime_rime_deploy(shared_data_dir, user_data_dir, false)) {
        return nullptr;
    }
    return create_session_internal();
}

extern "C" xime_rime_session *xime_rime_create_passive(const char *shared_data_dir,
                                                       const char *user_data_dir) {
    if (!shared_data_dir || !user_data_dir) {
        return nullptr;
    }
    if (!initialize_rime(shared_data_dir, user_data_dir)) {
        return nullptr;
    }
    return create_session_internal();
}

extern "C" void xime_rime_destroy(xime_rime_session *session) {
    if (!session) {
        return;
    }
    if (session->api) {
        session->api->destroy_session(session->id);
    }
    delete session;
}

extern "C" void xime_rime_reset(xime_rime_session *session) {
    if (!session || !session->api) {
        return;
    }
    session->api->clear_composition(session->id);
}

extern "C" char *xime_rime_process_key(xime_rime_session *session, int keycode,
                                       int modifiers) {
    if (!session || !session->api) {
        return nullptr;
    }
    session->api->process_key(session->id, keycode, modifiers);
    return build_result(session);
}

extern "C" char *xime_rime_process_key_fast(xime_rime_session *session, int keycode,
                                            int modifiers) {
    if (!session || !session->api) {
        return nullptr;
    }
    session->api->process_key(session->id, keycode, modifiers);
    return build_fast_result(session);
}

extern "C" char *xime_rime_context(xime_rime_session *session) {
    return build_result(session);
}

extern "C" char *xime_rime_select_candidate(xime_rime_session *session, int index) {
    if (!session || !session->api) {
        return nullptr;
    }
    // index 是当前页内的序号，与键盘候选栏一致。
    session->api->select_candidate_on_current_page(session->id,
                                                   static_cast<size_t>(index));
    return build_result(session);
}

extern "C" char *xime_rime_change_page(xime_rime_session *session, bool backward) {
    if (!session || !session->api) {
        return nullptr;
    }
    session->api->change_page(session->id, backward ? 1 : 0);
    return build_result(session);
}

extern "C" char *xime_rime_select_schema(xime_rime_session *session,
                                         const char *schema_id) {
    if (!session || !session->api || !schema_id) {
        return nullptr;
    }
    session->api->select_schema(session->id, schema_id);
    return build_result(session);
}

extern "C" char *xime_rime_commit(xime_rime_session *session) {
    if (!session || !session->api) {
        return nullptr;
    }
    session->api->commit_composition(session->id);
    return build_result(session);
}

extern "C" char *xime_rime_delete_backward(xime_rime_session *session) {
    if (!session || !session->api) {
        return nullptr;
    }
    constexpr int kXKBackSpace = 0xFF08;
    session->api->process_key(session->id, kXKBackSpace, 0);
    return build_result(session);
}

extern "C" char *xime_rime_set_option(xime_rime_session *session, const char *name,
                                      bool value) {
    if (!session || !session->api || !name) {
        return nullptr;
    }
    session->api->set_option(session->id, name, value ? 1 : 0);
    return build_result(session);
}

extern "C" char *xime_rime_status(xime_rime_session *session) {
    return build_result(session);
}

extern "C" void xime_rime_free_string(char *value) {
    std::free(value);
}
