#include "rubik.h"
#include "rubik_tables.h"

/* minirubik coordinates with the small endgame-table search described in
 * rubik.h. Search starts at the input; the final five moves come from a
 * sorted table. No full-state solution table is linked into the target.
 */
static const uint16_t *const pt[3] = {
    permutation_turns, permutation_turns + 5040, permutation_turns + 10080};
static const uint16_t *const ot[3] = {
    orientation_turns, orientation_turns + 729, orientation_turns + 1458};

#define ELEVEN_COUNT (sizeof distance_eleven / sizeof distance_eleven[0])
#define NO_ENTRY UINT32_MAX

static const uint8_t move_face[9] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t move_turns[9] = {1, 2, 3, 1, 2, 3, 1, 2, 3};

/* A 32-byte frame lets RV32I index the explicit stack with a shift. */
typedef struct {
    uint32_t p, o, np, no, face, turn, previous, unused;
} target_frame;
static target_frame frames[6];
static uint8_t result_path[11];

static int target_parse(const char *input, unsigned *gp, unsigned *go)
{
    unsigned seen = 0, p = 0, o = 0, sum = 0;
    static const unsigned weights[6] = {720, 120, 24, 6, 2, 1};

    for (unsigned i = 0; i < RUBIK_STATE_LEN; ++i) {
        if (input[i] == '\0')
            return 0;
    }
    if (input[RUBIK_STATE_LEN] != '\0')
        return 0;

    for (unsigned i = 0; i < 7; ++i) {
        unsigned digit = (unsigned) (unsigned char) input[i] - '1';
        if (digit >= 7 || (seen & (1u << digit)))
            return 0;
        seen |= 1u << digit;
    }
    for (unsigned i = 0; i < 6; ++i) {
        for (unsigned j = i + 1; j < 7; ++j) {
            if (input[j] < input[i])
                p += weights[i];
        }
    }
    for (unsigned i = 0; i < 7; ++i) {
        unsigned digit = (unsigned) (unsigned char) input[i + 7] - '1';
        if (digit >= 3)
            return 0;
        sum += digit;
        if (sum >= 3)
            sum -= 3;
        if (i < 6)
            o = (o << 1) + o + digit;
    }
    if (sum)
        return 0;
    *gp = p;
    *go = o;
    return 1;
}

/* Keys use shifts rather than p * 729 + o: orientation fits in ten bits.
 * A near-table entry is (key << 7) | (distance << 4) | move_toward_solved.
 */
static uint32_t find_near(unsigned p, unsigned o)
{
    uint32_t key = (p << 10) | o;
    /* Only entries with this permutation can match. The small offset index
     * avoids searching all 12,224 entries at every frontier node.
     */
    unsigned lo = near_offsets[p], hi = near_offsets[p + 1];
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        uint32_t entry = near_solved[mid], here = entry >> 7;
        if (here < key)
            lo = mid + 1;
        else if (here > key)
            hi = mid;
        else
            return entry;
    }
    return NO_ENTRY;
}

static int at_distance_eleven(unsigned p, unsigned o)
{
    uint32_t key = (p << 10) | o;
    unsigned lo = 0, hi = ELEVEN_COUNT;
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        uint32_t here = distance_eleven[mid];
        if (here < key)
            lo = mid + 1;
        else if (here > key)
            hi = mid;
        else
            return 1;
    }
    return 0;
}

/* Follow exact descending distances to recover the suffix, without search. */
static int finish_path(unsigned p, unsigned o, uint32_t entry, unsigned depth)
{
    unsigned remaining = (entry >> 4) & 7;
    while (remaining) {
        unsigned move = entry & 15, face = move_face[move];
        result_path[depth++] = (uint8_t) move;
        for (unsigned turns = move_turns[move]; turns; --turns) {
            p = pt[face][p];
            o = ot[face][o];
        }
        --remaining;
        if (remaining)
            entry = find_near(p, o);
    }
    return (int) depth;
}

/* Iterative deepening with an explicit stack and same-face pruning. A table
 * miss proves distance >= 6; the diameter table identifies exact distance 11.
 * All other inputs try increasing bounds up to 10. At five remaining moves,
 * one lookup replaces the entire subtree. The first solution is shortest.
 */
static int solve_coordinates(unsigned p, unsigned o)
{
    uint32_t entry = find_near(p, o);
    if (entry != NO_ENTRY)
        return finish_path(p, o, entry, 0);

    unsigned first = 6, last = 10;
    if (at_distance_eleven(p, o)) {
        first = 11;
        last = 11;
    } else {
        if (permutation_distance[p] > first)
            first = permutation_distance[p];
        if (orientation_distance[o] > first)
            first = orientation_distance[o];
    }
    for (unsigned bound = first; bound <= last; ++bound) {
        unsigned depth = 0;
        frames[0] = (target_frame) {p, o, p, o, 0, 0, 3, 0};
        for (;;) {
            target_frame *f = &frames[depth];
            if (f->face == 3) {
                if (depth == 0)
                    break;
                --depth;
                continue;
            }
            unsigned face = f->face;
            if (face == f->previous) {
                ++f->face;
                continue;
            }
            unsigned np = pt[face][f->np], no = ot[face][f->no];
            unsigned turn = f->turn++;
            if (f->turn == 3) {
                ++f->face;
                f->turn = 0;
                f->np = f->p;
                f->no = f->o;
            } else {
                f->np = np;
                f->no = no;
            }
            unsigned remaining = bound - depth - 1;
            if (permutation_distance[np] > remaining ||
                orientation_distance[no] > remaining)
                continue;
            result_path[depth] = (uint8_t) ((face << 1) + face + turn);
            if (remaining == 5) {
                entry = find_near(np, no);
                if (entry != NO_ENTRY)
                    return finish_path(np, no, entry, depth + 1);
                continue;
            }
            ++depth;
            frames[depth] = (target_frame) {np, no, np, no, 0, 0, face, 0};
        }
    }
    return -1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    unsigned gp, go;
    if (!target_parse(state, &gp, &go))
        return -1;
    if (cap == 0)
        return -2;
    if (gp == 0 && go == 0) {
        out[0] = '\0';
        return 0;
    }

    int length = solve_coordinates(gp, go);
    if (length < 0)
        return -1;

    /* Moves now run directly from the input to solved. Build locally so an
     * undersized buffer never receives a partial answer.
     */
    static const char faces[] = "RBD", suffix[] = "2'";
    char solution[3 * 11];
    size_t used = 0;
    for (unsigned i = 0; i < (unsigned) length; ++i) {
        unsigned move = result_path[i], face = move_face[move];
        if (used)
            solution[used++] = ' ';
        solution[used++] = faces[face];
        unsigned turns = move_turns[move];
        if (turns > 1)
            solution[used++] = suffix[turns - 2];
    }
    if (used + 1 > cap) {
        out[0] = '\0';
        return -2;
    }
    solution[used] = '\0';
    for (size_t i = 0; i <= used; ++i)
        out[i] = solution[i];
    return length;
}
