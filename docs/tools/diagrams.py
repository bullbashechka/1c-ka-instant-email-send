# Draws the diagrams of section 3. Usage: python3 docs/tools/diagrams.py docs/img
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle

plt.rcParams["font.family"] = "PT Sans"
OUT = sys.argv[1]

# 1 unit = 0.064 in: 106 units ~ 6.8 in, the text width of an A4 page. Font sizes are final print sizes.
SCALE = 0.064
FS = 8.5
FS_SMALL = 7.5

INK = "#1f2933"
MUTED = "#52606d"
LINE = "#7b8794"
BLUE, BLUE_BG = "#2f6fb0", "#eaf2fb"
GREEN, GREEN_BG = "#2e7d4f", "#e6f4ea"
AMBER, AMBER_BG = "#a86a00", "#fff4dc"
RED, RED_BG = "#b3261e", "#fde8e6"
LANE_BG = "#f2f4f7"


def rect(ax, x, y, w, h, edge, face, r=1.2, lw=1.2):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0,rounding_size={r}",
                                fc=face, ec=edge, lw=lw, zorder=3))


def box(ax, x, y, w, h, text, edge=BLUE, face="white", size=FS):
    rect(ax, x, y, w, h, edge, face)
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=size, color=INK,
            zorder=4, linespacing=1.25)


def result(ax, x, y, w, h, cond, title, body, edge, face):
    rect(ax, x, y, w, h, edge, face)
    cx = x + w / 2
    ax.text(cx, y + h - 1.6, cond, ha="center", va="top", fontsize=FS_SMALL, color=MUTED,
            style="italic", zorder=4)
    ax.text(cx, y + h - 4.4, title, ha="center", va="top", fontsize=FS + 0.5, color=edge,
            fontweight="bold", zorder=4)
    ax.text(cx, y + h - 7.6, body, ha="center", va="top", fontsize=FS_SMALL + 0.5, color=INK,
            zorder=4, linespacing=1.25)


def badge(ax, x, y, n, color=BLUE):
    ax.add_patch(Circle((x, y), 1.8, fc=color, ec="white", lw=1.2, zorder=5))
    ax.text(x, y - 0.05, str(n), ha="center", va="center", fontsize=FS, fontweight="bold",
            color="white", zorder=6)


def arrow(ax, p1, p2, color=LINE, rad=0.0, ls="-", style=None):
    ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle="-|>", mutation_scale=9, lw=1.2,
                                 color=color, ls=ls, zorder=2,
                                 connectionstyle=style or f"arc3,rad={rad}",
                                 shrinkA=0, shrinkB=0))


def label(ax, x, y, text, ha="center", color=MUTED):
    ax.text(x, y, text, ha=ha, va="center", fontsize=FS_SMALL, color=color, style="italic",
            zorder=4, linespacing=1.2, bbox=dict(fc="white", ec="none", pad=0.8, alpha=0.95))


def new(w, h):
    fig, ax = plt.subplots(figsize=(w * SCALE, h * SCALE))
    ax.set_xlim(0, w)
    ax.set_ylim(0, h)
    ax.axis("off")
    fig.subplots_adjust(0, 0, 1, 1)
    return fig, ax


def save(fig, name):
    fig.savefig(f"{OUT}/{name}.png", dpi=300)
    plt.close(fig)


# ---------- 1. Общая схема ----------
fig, ax = new(106, 62)
lanes = [(42, 62, "Пользователь\nи форма\nписьма"), (21, 42, "Сервер 1С,\nфоновое\nзадание"),
         (0, 21, "Почтовый\nсервер")]
for i, (y0, y1, name) in enumerate(lanes):
    ax.add_patch(FancyBboxPatch((0.3, y0 + 0.4), 105.4, y1 - y0 - 0.8,
                                boxstyle="round,pad=0,rounding_size=1.2",
                                fc=LANE_BG if i != 1 else "#f8f9fb", ec="#d9dee5", lw=0.8, zorder=0))
    ax.text(6.5, (y0 + y1) / 2, name, ha="center", va="center", fontsize=FS - 0.5, fontweight="bold",
            color=MUTED, linespacing=1.2)

W, H = 20, 14
C = [14, 38, 62, 85.5]          # column x
YA, YB, YC = 45, 24.5, 3.5      # lane box y

box(ax, C[0] + 1.5, YA, W - 1.5, H, "Нажимает\n«Отправить»")
box(ax, C[1], YA, W, H, "Письмо записано\nв «Исходящие»\nи спрятано\nот регламентного\nзадания на 10 мин")
box(ax, C[2], YA, W, H, "Окно закрылось,\nпользователь\nработает дальше")
box(ax, C[3], YA, W, H, "Оповещение\n«Письмо отправлено»\nили ошибка", edge=GREEN, face=GREEN_BG)
box(ax, C[1], YB, W, H, "Занимает\nучётную запись\n(если занята —\nждёт до 5 минут)")
box(ax, C[2], YB, W, H, "Отправляет письмо:\nдо 3 попыток\n(сразу, через 10 с,\nчерез 30 с)")
box(ax, C[3], YB, W, H, "Записывает\nрезультат в письмо,\nосвобождает\nучётную запись")
box(ax, C[2], YC, W, H, "Принимает\nписьмо", edge=LINE)

for x, y, n in [(C[0] + 1.5, YA, 1), (C[1], YA, 2), (C[2], YA, 3), (C[1], YB, 4), (C[2], YB, 5),
                (C[2], YC, 6), (C[3], YB, 7), (C[3], YA, 8)]:
    badge(ax, x + 0.6, y + H - 0.6, n, GREEN if n == 8 else BLUE)

mid = H / 2
arrow(ax, (C[0] + W, YA + mid), (C[1], YA + mid))
arrow(ax, (C[1] + W, YA + mid), (C[2], YA + mid))
arrow(ax, (C[1] + W / 2, YA), (C[1] + W / 2, YB + H))
label(ax, C[1] + W / 2, (YA + YB + H) / 2, "запуск задания")
arrow(ax, (C[1] + W, YB + mid), (C[2], YB + mid))
arrow(ax, (C[2] + W / 2, YB), (C[2] + W / 2, YC + H))
label(ax, C[2] + W / 2, (YB + YC + H) / 2, "письмо")
arrow(ax, (C[2] + W, YC + mid), (C[3] + W / 2, YB), rad=0.3)
label(ax, C[3] + W / 2 - 1.5, YC + mid - 1, "ответ сервера")
arrow(ax, (C[3] + W / 2, YB + H), (C[3] + W / 2, YA))
label(ax, C[3] + W / 2, (YA + YB + H) / 2, "результат")
save(fig, "схема-отправки")


# ---------- 2. Попытки и итоги ----------
fig, ax = new(106, 66)
box(ax, 2, 45, 22, 13, "Попытка\nотправки", size=FS + 1)
rect(ax, 29, 45, 22, 13, BLUE, BLUE_BG, r=5)
ax.text(40, 51.5, "Что ответил\nпочтовый\nсервер?", ha="center", va="center", fontsize=FS + 0.5,
        fontweight="bold", color=INK, zorder=4, linespacing=1.2)
arrow(ax, (24, 51.5), (29, 51.5))

RX, RW, RH = 58, 47.5, 14.5
rows = [
    (50.5, "сервер принял письмо", "Отправлено",
     "Письмо в «Отправленных»,\nоповещение «Письмо отправлено»", GREEN, GREEN_BG),
    (34, "сервер принял не всех адресатов", "Отправлено остальным",
     "Оповещение и предупреждение со списком\nнепринятых адресов", GREEN, GREEN_BG),
    (17.5, "не принят ни один адресат или письмо не подготовить", "Возвращено в «Черновики»",
     "Открывается форма письма с ошибкой,\nпользователь исправляет и отправляет снова", AMBER, AMBER_BG),
    (1, "нет связи, неверный логин, пароль, порт, шифрование", "Не отправлено (после 3-й попытки)",
     "Письмо остаётся в «Исходящих», его отправит\nрегламентное задание. Окно ошибки и оповещение", RED, RED_BG),
]
TX = 54.5
ax.plot([51, TX], [51.5, 51.5], color=LINE, lw=1.2, zorder=2)
ax.plot([TX, TX], [rows[0][0] + RH / 2, rows[-1][0] + RH / 2], color=LINE, lw=1.2, zorder=2)
for y, cond, title, body, edge, face in rows:
    result(ax, RX, y, RW, RH, cond, title, body, edge, face)
    arrow(ax, (TX, y + RH / 2), (RX, y + RH / 2), color=edge)

arrow(ax, (RX, 4), (13, 45), color=RED, ls=(0, (3, 2)), style="angle,angleA=180,angleB=-90,rad=3")
ax.text(15, 24, "Остались попытки?\nПауза 10 с перед 2-й\nи 30 с перед 3-й,\nзатем снова попытка",
        ha="left", va="center", fontsize=FS_SMALL + 0.5, color=RED, zorder=4, linespacing=1.25)
save(fig, "попытки-и-итоги")


# ---------- 3. Защита от двойной отправки ----------
fig, ax = new(106, 33)
ax.text(53, 30, "Письмо, которое сейчас отправляется, видит только мгновенная отправка",
        ha="center", va="center", fontsize=FS + 1, color=INK, fontweight="bold")
BW = 30
box(ax, 1, 10, BW, 15, "Мгновенная отправка\nставит в «Когда отправить»\n«сейчас + 10 минут»")
box(ax, 38, 10, BW, 15, "Регламентное задание\nи «Отправить и получить\nпочту» видят время\nв будущем и пропускают\nписьмо", edge=LINE)
box(ax, 75, 10, BW, 15, "После отправки поле\nочищается той же записью,\nкоторая ставит статус\n«Отправлено»", edge=GREEN, face=GREEN_BG)
arrow(ax, (1 + BW, 17.5), (38, 17.5))
arrow(ax, (38 + BW, 17.5), (75, 17.5))
ax.text(53, 4, "Затянувшаяся отправка продлевает служебное время. Если отправка оборвалась (например, перезапустили\n"
        "сервер 1С), время истечёт само не позже чем через 10 минут, и письмо отправит регламентное задание.",
        ha="center", va="center", fontsize=FS_SMALL, color=MUTED, linespacing=1.3)
save(fig, "защита-от-двойной-отправки")
print("ok")
