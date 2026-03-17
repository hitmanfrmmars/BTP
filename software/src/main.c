#include "gemm_accel.h"

/*
 * Demo firmware: 4x4 int8 GEMM via the accelerator driver.
 *
 * Matrices are placed at fixed addresses in SoC memory:
 *   A at 0x00010000  (4x4 int8, row-major, packed 4 per word)
 *   B at 0x00010100  (4x4 int8, row-major, packed 4 per word)
 *   C at 0x00010200  (4x4 int8 result)
 *
 * After the GEMM completes, the firmware reads back C and
 * compares against the expected golden result.  Pass/fail
 * and cycle count are written to the debug port.
 */

#define ADDR_A  0x00010000u
#define ADDR_B  0x00010100u
#define ADDR_C  0x00010200u

#define M 4
#define K 4
#define N 4

/* Debug markers */
#define MARKER_PASS  0x0000600Du   /* "GOOD" */
#define MARKER_FAIL  0x0000FA11u   /* "FAIL" */
#define MARKER_DONE  0x0000DEADu

static void init_matrices(void)
{
    volatile uint32_t *a = (volatile uint32_t *)ADDR_A;
    volatile uint32_t *b = (volatile uint32_t *)ADDR_B;

    /* A = [[1,2,0,0], [0,1,2,0], [0,0,1,2], [1,0,0,1]] */
    a[0] = pack4_u8(1, 2, 0, 0);
    a[1] = pack4_u8(0, 1, 2, 0);
    a[2] = pack4_u8(0, 0, 1, 2);
    a[3] = pack4_u8(1, 0, 0, 1);

    /* B = [[1,1,0,0], [0,1,1,0], [0,0,1,1], [1,0,0,1]] */
    b[0] = pack4_u8(1, 1, 0, 0);
    b[1] = pack4_u8(0, 1, 1, 0);
    b[2] = pack4_u8(0, 0, 1, 1);
    b[3] = pack4_u8(1, 0, 0, 1);
}

/*
 * Expected C = A * B:
 *   [[1,3,2,0], [0,1,3,2], [2,0,1,3], [2,1,0,1]]
 */
static const uint32_t expected_c[4] = {
    0x00020301u,  /* pack4_u8(1,3,2,0) */
    0x02030100u,  /* pack4_u8(0,1,3,2) */
    0x03010002u,  /* pack4_u8(2,0,1,3) */
    0x01000102u,  /* pack4_u8(2,1,0,1) */
};

static int verify_result(void)
{
    volatile uint32_t *c = (volatile uint32_t *)ADDR_C;
    int errors = 0;

    for (int i = 0; i < M; i++) {
        if (c[i] != expected_c[i])
            errors++;
    }
    return errors;
}

int main(void)
{
    /* Step 1: Write test matrices to memory */
    init_matrices();

    /* Step 2: Run int8 GEMM through the accelerator */
    gemm_result_t res = gemm_run_int8(
        M, K, N,
        ADDR_A, ADDR_B, ADDR_C,
        K,          /* stride_a = K bytes (K columns * 1 byte) */
        N,          /* stride_b = N bytes */
        N           /* stride_c = N bytes (int8 output) */
    );

    /* Step 3: Report cycle count */
    debug_putw(res.cycles);

    /* Step 4: Verify results */
    int errors = verify_result();

    if (errors == 0)
        debug_putw(MARKER_PASS);
    else
        debug_putw(MARKER_FAIL);

    /* Step 5: Completion marker */
    debug_putw(MARKER_DONE);

    return 0;
}
