// 在 macOS 上预生成 Rime 词典，供键盘扩展直接加载。
#include "RimeBridgeC.h"

#include <cstdio>

int main(int argc, char **argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: %s <shared_data_dir> <user_data_dir>\n", argv[0]);
        return 64;
    }
    if (!xime_rime_deploy(argv[1], argv[2], true)) {
        std::fprintf(stderr, "deploy failed\n");
        return 1;
    }
    std::printf("predeploy ok: %s\n", argv[2]);
    return 0;
}
