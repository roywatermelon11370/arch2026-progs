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
    int n;
    return op1(a, op1(~b, 1, &n), &n);
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint64_t multiplicand = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t multiplier = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    uint64_t product = 0;

    while (multiplier) {
        if (multiplier & 1u)
            product += multiplicand;
        multiplicand <<= 1;
        multiplier >>= 1;
    }

    if ((a < 0) != (b < 0))
        product = 0u - product;
    product += UINT64_C(1) << (Q - 1);

    return (int32_t) (uint32_t) (product >> Q);
}
