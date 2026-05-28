#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "array_mode0_32b_32b_32_32_32_random.h"

/*
 * matmul
 * ----------
 * Compute matrix multiplication with bias and store results in C.
 *
 * Parameters:
 *   A  - pointer to input matrix A with dimensions M_d x K_d.
 *        Stored row-major: element A(i,k) is at A[i * K_d + k].
 *   W  - pointer to weights matrix W with dimensions N_d x K_d.
 *        Stored row-major: element W(n,k) is at W[n * K_d + k].
 *        Note: W is laid out so row index corresponds to output column 'n'.
 *   C  - output buffer for the result matrix with dimensions M_d x N_d.
 *        Stored row-major: element C(i,n) is at C[i * N_d + n].
 *
 * Behavior notes:
 *   - The inner accumulation uses C_TYPE-bit arithmetic. If inputs or K_d are
 *     large enough to cause overflow, results will wrap/truncate when stored to C. 
 *     However, the provided test data and dimensions are chosen to avoid overflow in this example.
 *   - bias[n] is added per output column n; bias comes from the included header.
 */
void matmul(const I_TYPE A[M_d * K_d], const W_TYPE W[N_d * K_d], C_TYPE C[M_d * N_d]) {
	for (int i = 0; i < M_d; ++i) {
		for (int n = 0; n < N_d; ++n) {
			C_TYPE sum = 0;
			/* accumulate dot product of row i of A and row n of W (which corresponds to column n) */
			for (int k = 0; k < K_d; ++k) {
				I_TYPE a = A[i * K_d + k];  /* A(i,k) */
				W_TYPE w = W[n * K_d + k];  /* W(n,k) */
				sum += a * w;
			}
			/* add bias for output column n and write final (possibly truncated) C_TYPE result */
			sum += bias[n];
			C[i * N_d + n] = sum;
		}
	}
}

/*
 * compare_matrix
 * ----------
 * Element-wise compare two M_d x N_d matrices.
 *
 * Parameters:
 *   C    - computed result matrix (M_d * N_d elements), row-major.
 *   gold - reference (golden) matrix to compare against, same layout as C.
 *
 * Output:
 *   Prints up to the first 16 mismatches with (row,col): got vs expected values.
 *   Returns the total number of mismatches (0 means exact match).
 */
int compare_matrix(const C_TYPE C[M_d * N_d], const C_TYPE gold[M_d * N_d]) {
	int errors = 0;
	for (int i = 0; i < M_d * N_d; ++i) {
		C_TYPE g = gold[i];
		if (C[i] != g) {
			if (errors < 16) {
				int row = i / N_d;
				int col = i % N_d;
				printf("mismatch at (%d,%d): got %d expected %d\n", row, col, C[i], g);
			}
			errors++;
		}
	}
	if (errors == 0) {
		printf("PASS: all elements match golden.\n");
	} else {
		printf("FAIL: %d mismatches\n", errors);
	}
	return errors;
}

int main(void) {
	/* Compile-time output buffer sized for M_d x N_d (stack-allocated).
	 * Using a fixed-size array makes the storage lifetime and size obvious to students.
	 */
	C_TYPE result[M_d * N_d];

	/* Compute matrix product into 'result' and compare against the golden reference
	 * provided by the included header. The 'golden' symbol must be compatible with
	 * C_TYPE layout for correct comparison.
	 */
	matmul(input_unpacked, weights_unpacked, result);
	int errs = compare_matrix(result, golden);

	return (errs == 0) ? 0 : 1;
}
