#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b) {
        unsigned c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++*n;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t multiplicand_low = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t multiplicand_high = 0;
    uint32_t multiplier = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    uint32_t product_low = 0;
    uint32_t product_high = 0;

    while (multiplier) {
        if (multiplier & 1u) {
            uint32_t sum = product_low + multiplicand_low;
            product_high += multiplicand_high + (sum < product_low);
            product_low = sum;
        }
        multiplicand_high = (multiplicand_high << 1) | (multiplicand_low >> 31);
        multiplicand_low <<= 1;
        multiplier >>= 1;
    }

    /* Negate both words, carrying into the high word when the low is zero. */
    if ((a < 0) != (b < 0)) {
        product_high = ~product_high + (product_low == 0);
        product_low = ~product_low + 1u;
    }

    /* Round before shifting and propagate any carry into the high word. */
    product_high += product_low > UINT32_MAX - (1u << (Q - 1));
    uint32_t rounded_low = product_low + (1u << (Q - 1));
    return (int32_t) ((rounded_low >> Q) | (product_high << (32 - Q)));
}
