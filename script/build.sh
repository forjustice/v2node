#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 默认参数
VERSION=""
GOOS=$(go env GOOS)
GOARCH=$(go env GOARCH)

# 显示使用说明
show_usage() {
    echo "用法: $0 [版本号] [选项]"
    echo ""
    echo "选项:"
    echo "  -v, --version VERSION    指定版本号（必需）"
    echo "  -o, --os OS             目标操作系统 (linux/darwin/windows，默认: 当前系统)"
    echo "  -a, --arch ARCH         目标架构 (amd64/arm64/386 等，默认: 当前架构)"
    echo "  -h, --help              显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -v 0.2.0.a"
    echo "  $0 -v 0.2.0.a -o linux -a amd64"
    echo "  $0 --version 0.2.0.a --os linux --arch arm64"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"; shift 2 ;;
        -o|--os)
            GOOS="$2"; shift 2 ;;
        -a|--arch)
            GOARCH="$2"; shift 2 ;;
        -h|--help)
            show_usage ;;
        *)
            # 兼容直接传入版本号
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"; shift
            else
                echo -e "${red}未知参数: $1${plain}"
                show_usage
            fi ;;
    esac
done

# 检查版本号
if [[ -z "$VERSION" ]]; then
    echo -e "${red}错误: 必须指定版本号${plain}"
    show_usage
fi

# 检查是否在项目根目录
if [[ ! -f "main.go" ]] || [[ ! -f "go.mod" ]]; then
    echo -e "${red}错误: 请在项目根目录运行此脚本${plain}"
    exit 1
fi

# 检查 Go 环境
if ! command -v go &> /dev/null; then
    echo -e "${red}错误: 未找到 Go 环境${plain}"
    exit 1
fi

echo -e "${green}========================================${plain}"
echo -e "${green}V2node 构建脚本${plain}"
echo -e "${green}========================================${plain}"
echo -e "版本号: ${green}$VERSION${plain}"
echo -e "目标系统: ${green}$GOOS${plain}"
echo -e "目标架构: ${green}$GOARCH${plain}"
echo -e "${green}========================================${plain}"

# 创建构建目录
BUILD_DIR="build_assets"
echo -e "${yellow}[1/6] 创建构建目录...${plain}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 下载依赖
echo -e "${yellow}[2/6] 下载 Go 依赖...${plain}"
go mod download

# 构建二进制文件
echo -e "${yellow}[3/6] 编译 v2node...${plain}"
OUTPUT_NAME="v2node"
if [[ "$GOOS" == "windows" ]]; then
    OUTPUT_NAME="v2node.exe"
fi

CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" GOEXPERIMENT=jsonv2 go build \
    -v \
    -o "$BUILD_DIR/$OUTPUT_NAME" \
    -trimpath \
    -ldflags "-X 'github.com/wyx2685/v2node/cmd.version=$VERSION' -s -w -buildid=" \
    .

if [[ $? -ne 0 ]]; then
    echo -e "${red}错误: 编译失败${plain}"
    exit 1
fi

echo -e "${green}编译成功: $BUILD_DIR/$OUTPUT_NAME${plain}"

# 下载 geo 文件
echo -e "${yellow}[4/6] 下载 geoip.dat 和 geosite.dat...${plain}"
GEO_FILES=('geoip' 'geosite')
for file in "${GEO_FILES[@]}"; do
    DOWNLOAD_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/${file}.dat"
    echo -e "  下载 ${file}.dat..."

    # 尝试下载，最多重试 3 次
    MAX_RETRIES=3
    RETRY_COUNT=0
    SUCCESS=false

    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        if curl -fsSL --connect-timeout 30 --max-time 120 "$DOWNLOAD_URL" -o "$BUILD_DIR/${file}.dat"; then
            # 验证文件是否成功下载（大于 1KB）
            if [[ -f "$BUILD_DIR/${file}.dat" ]] && [[ $(wc -c < "$BUILD_DIR/${file}.dat") -gt 1024 ]]; then
                SUCCESS=true
                break
            fi
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            echo -e "  ${yellow}重试 ($((RETRY_COUNT + 1))/$MAX_RETRIES)...${plain}"
            sleep 2
        fi
    done

    if [[ "$SUCCESS" == "false" ]]; then
        echo -e "${red}警告: 下载 ${file}.dat 失败${plain}"
    fi
done

# 复制文档
echo -e "${yellow}[5/6] 复制 README 和 LICENSE...${plain}"
cp README.md "$BUILD_DIR/" 2>/dev/null || echo -e "${yellow}警告: 未找到 README.md${plain}"
cp LICENSE "$BUILD_DIR/" 2>/dev/null || echo -e "${yellow}警告: 未找到 LICENSE${plain}"

# 创建配置文件模板
cat > "$BUILD_DIR/config.json" <<'EOF'
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
    },
    "Nodes": [
        {
            "ApiHost": "http://127.0.0.1:667",
            "NodeID": 41,
            "ApiKey": "123",
            "Timeout": 30
        }
    ]
}
EOF

# 打包
echo -e "${yellow}[6/6] 创建 ZIP 压缩包...${plain}"
ASSET_NAME="${GOOS}-${GOARCH}"
ZIP_NAME="v2node-${VERSION}-${ASSET_NAME}.zip"

cd "$BUILD_DIR" || exit 1
zip -9qr "../$ZIP_NAME" .
cd .. || exit 1

# 生成校验和
echo -e "${yellow}生成校验和...${plain}"
DGST_FILE="${ZIP_NAME}.dgst"
> "$DGST_FILE"
for METHOD in md5 sha1 sha256 sha512; do
    if command -v ${METHOD}sum &> /dev/null; then
        ${METHOD}sum "$ZIP_NAME" >> "$DGST_FILE"
    elif command -v openssl &> /dev/null; then
        openssl dgst -$METHOD "$ZIP_NAME" | sed 's/([^)]*)//g' >> "$DGST_FILE"
    fi
done

echo -e "${green}========================================${plain}"
echo -e "${green}构建完成！${plain}"
echo -e "${green}========================================${plain}"
echo -e "构建目录: ${green}$BUILD_DIR/${plain}"
echo -e "压缩包: ${green}$ZIP_NAME${plain}"
echo -e "校验和: ${green}$DGST_FILE${plain}"
echo ""
echo -e "${yellow}文件列表:${plain}"
ls -lh "$BUILD_DIR"
echo ""
echo -e "${yellow}验证版本号:${plain}"
if [[ "$GOOS" == "$(go env GOOS)" ]] && [[ "$GOARCH" == "$(go env GOARCH)" ]]; then
    "./$BUILD_DIR/$OUTPUT_NAME" version
else
    echo -e "${yellow}跨平台编译，无法在当前系统验证${plain}"
fi
