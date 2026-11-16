/* Host-only table generator. The face model and coordinate ranking follow
 * minirubik; the target links only the emitted tables, never the full BFS.
 *
 * gcc -std=c99 -O2 tools/gen_rubik_tables.c -o build/gen_rubik_tables
 * build/gen_rubik_tables src/rubik/rubik_tables.h
 * build/gen_rubik_tables --asm src/rubik/rubik_tables.S
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { PERMUTATIONS = 5040, ORIENTATIONS = 729, STATES = 3674160 };
static const uint8_t source[3][7] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][7] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};
static const unsigned factorial[7] = {720, 120, 24, 6, 2, 1, 1};
static uint16_t pt[3 * PERMUTATIONS], ot[3 * ORIENTATIONS];
static int assembly_output;

static unsigned rank_permutation(const uint8_t p[7])
{
    unsigned rank = 0;
    for (unsigned i = 0; i < 6; ++i) {
        for (unsigned j = i + 1; j < 7; ++j) {
            if (p[j] < p[i])
                rank += factorial[i];
        }
    }
    return rank;
}

static void build_turns(void)
{
    for (unsigned rank = 0; rank < PERMUTATIONS; ++rank) {
        uint8_t available[7] = {0, 1, 2, 3, 4, 5, 6}, p[7], next[7];
        unsigned rest = rank;
        for (unsigned i = 0; i < 7; ++i) {
            unsigned digit = rest / factorial[i];
            rest %= factorial[i];
            p[i] = available[digit];
            for (unsigned j = digit; j + 1 < 7 - i; ++j)
                available[j] = available[j + 1];
        }
        for (unsigned face = 0; face < 3; ++face) {
            for (unsigned i = 0; i < 7; ++i)
                next[i] = p[source[face][i]];
            pt[face * PERMUTATIONS + rank] = (uint16_t) rank_permutation(next);
        }
    }
    for (unsigned rank = 0; rank < ORIENTATIONS; ++rank) {
        uint8_t o[7];
        unsigned rest = rank, sum = 0;
        for (unsigned i = 6; i-- > 0;) {
            o[i] = (uint8_t) (rest % 3);
            rest /= 3;
            sum += o[i];
        }
        o[6] = (uint8_t) ((3 - sum % 3) % 3);
        for (unsigned face = 0; face < 3; ++face) {
            unsigned next = 0;
            for (unsigned i = 0; i < 6; ++i)
                next = next * 3 + (o[source[face][i]] + twist[face][i]) % 3;
            ot[face * ORIENTATIONS + rank] = (uint16_t) next;
        }
    }
}

static void build_relaxed(unsigned count,
                          const uint16_t *turns,
                          uint8_t *distance,
                          uint32_t *queue)
{
    for (unsigned i = 0; i < count; ++i)
        distance[i] = 255;
    distance[0] = 0;
    queue[0] = 0;
    unsigned head = 0, tail = 1;
    while (head < tail) {
        unsigned here = queue[head++];
        for (unsigned face = 0; face < 3; ++face) {
            unsigned there = here;
            for (unsigned turn = 0; turn < 3; ++turn) {
                there = turns[face * count + there];
                if (distance[there] == 255) {
                    distance[there] = (uint8_t) (distance[here] + 1);
                    queue[tail++] = there;
                }
            }
        }
    }
}

static void emit_table(FILE *out,
                       const char *type,
                       const char *name,
                       const void *values,
                       unsigned count,
                       unsigned width)
{
    if (assembly_output)
        fprintf(out,
                "    .balign 4\n    .globl rubik_asm_%s\n"
                "    .type rubik_asm_%s, @object\nrubik_asm_%s:\n",
                name, name, name);
    else
        fprintf(out, "static const %s %s[%u] = {\n", type, name, count);
    for (unsigned i = 0; i < count; ++i) {
        unsigned value;
        if (width == 1)
            value = ((const uint8_t *) values)[i];
        else if (width == 2)
            value = ((const uint16_t *) values)[i];
        else
            value = ((const uint32_t *) values)[i];
        if (i % 12 == 0) {
            fputs("    ", out);
            if (assembly_output)
                fputs(width == 1   ? ".byte "
                      : width == 2 ? ".half "
                                   : ".word ",
                      out);
        }
        fprintf(out, "%u", value);
        if (!assembly_output || (i % 12 != 11 && i + 1 != count))
            fputc(',', out);
        fputc(i % 12 == 11 || i + 1 == count ? '\n' : ' ', out);
    }
    if (assembly_output)
        fprintf(out, "    .size rubik_asm_%s, .-rubik_asm_%s\n\n", name, name);
    else
        fputs("};\n\n", out);
}

int main(int argc, char **argv)
{
    assembly_output = argc == 3 && strcmp(argv[1], "--asm") == 0;
    if (argc != 2 && !assembly_output) {
        fprintf(stderr, "usage: %s [--asm] output-file\n", argv[0]);
        return 1;
    }
    uint8_t *distance = malloc(STATES), *toward = malloc(STATES);
    uint32_t *queue = malloc((size_t) STATES * sizeof(*queue));
    if (!distance || !toward || !queue) {
        free(distance);
        free(toward);
        free(queue);
        return 1;
    }
    build_turns();
    for (unsigned i = 0; i < STATES; ++i)
        distance[i] = 255;
    distance[0] = 0;
    toward[0] = 9;
    queue[0] = 0;
    unsigned head = 0, tail = 1, diameter = 0;
    while (head < tail) {
        unsigned here = queue[head++], p = here / ORIENTATIONS;
        unsigned o = here % ORIENTATIONS;
        for (unsigned face = 0; face < 3; ++face) {
            unsigned np = p, no = o;
            for (unsigned turn = 0; turn < 3; ++turn) {
                np = pt[face * PERMUTATIONS + np];
                no = ot[face * ORIENTATIONS + no];
                unsigned there = np * ORIENTATIONS + no;
                if (distance[there] != 255)
                    continue;
                distance[there] = (uint8_t) (distance[here] + 1);
                toward[there] = (uint8_t) (face * 3 + 2 - turn);
                queue[tail++] = there;
                if (distance[there] > diameter)
                    diameter = distance[there];
            }
        }
    }
    unsigned near_count = 0, far_count = 0;
    for (unsigned i = 0; i < STATES; ++i) {
        near_count += distance[i] <= 5;
        far_count += distance[i] == 11;
    }
    if (tail != STATES || diameter != 11 || near_count != 12224 ||
        far_count != 2644) {
        fprintf(stderr, "unexpected cube graph\n");
        free(distance);
        free(toward);
        free(queue);
        return 1;
    }

    /* Sorted by (p << 10) | o. Low bits of each near entry hold the exact
     * distance (bits 6..4) and one move toward solved (bits 3..0).
     */
    unsigned near_index = 0, far_index = near_count;
    for (unsigned i = 0; i < STATES; ++i) {
        unsigned key = ((i / ORIENTATIONS) << 10) | (i % ORIENTATIONS);
        if (distance[i] <= 5)
            queue[near_index++] =
                (key << 7) | ((unsigned) distance[i] << 4) | toward[i];
        if (distance[i] == 11)
            queue[far_index++] = key;
    }
    uint16_t near_offsets[PERMUTATIONS + 1];
    unsigned offset = 0;
    for (unsigned p = 0; p < PERMUTATIONS; ++p) {
        near_offsets[p] = (uint16_t) offset;
        for (unsigned o = 0; o < ORIENTATIONS; ++o)
            offset += distance[p * ORIENTATIONS + o] <= 5;
    }
    near_offsets[PERMUTATIONS] = (uint16_t) offset;
    FILE *out = fopen(argv[assembly_output ? 2 : 1], "w");
    if (!out) {
        free(distance);
        free(toward);
        free(queue);
        return 1;
    }
    if (assembly_output)
        fputs(
            "# Generated by tools/gen_rubik_tables.c --asm. Do not edit "
            "entries.\n"
            "# Same small coordinate/endgame tables as rubik_tables.h.\n"
            "    .section .rodata\n\n",
            out);
    else
        fputs(
            "/* Generated by tools/gen_rubik_tables.c. Do not edit entries.\n"
            " * Face model: minirubik. Only small lookup tables reach the "
            "target.\n"
            " */\n#pragma once\n\n#include <stdint.h>\n\n",
            out);
    emit_table(out, "uint16_t", "permutation_turns", pt, 3 * PERMUTATIONS, 2);
    emit_table(out, "uint16_t", "orientation_turns", ot, 3 * ORIENTATIONS, 2);
    emit_table(out, "uint32_t", "near_solved", queue, near_count, 4);
    emit_table(out, "uint16_t", "near_offsets", near_offsets, PERMUTATIONS + 1,
               2);
    emit_table(out, "uint32_t", "distance_eleven", queue + near_count,
               far_count, 4);
    uint8_t pd[PERMUTATIONS], od[ORIENTATIONS];
    build_relaxed(PERMUTATIONS, pt, pd, queue);
    build_relaxed(ORIENTATIONS, ot, od, queue);
    emit_table(out, "uint8_t", "permutation_distance", pd, PERMUTATIONS, 1);
    emit_table(out, "uint8_t", "orientation_distance", od, ORIENTATIONS, 1);
    if (assembly_output)
        fputs("# End of generated tables.\n", out);
    int failed = ferror(out);
    if (fclose(out) != 0)
        failed = 1;
    fprintf(stderr, "%u states; diameter %u; near %u; distance-11 %u\n", tail,
            diameter, near_count, far_count);
    free(distance);
    free(toward);
    free(queue);
    return failed ? 1 : 0;
}
