def fib(n) {
  if (n < 2) { return n; }
  return fib(n-1) + fib(n-2);
}

def bubbleSort(arr) {
  let n = len(arr);
  let i = 0;
  while (i < n) {
    let j = 0;
    while (j < n - i - 1) {
      if (arr[j] > arr[j + 1]) {
        let temp = arr[j];
        arr[j] = arr[j + 1];
        let jPlusOne = j + 1;
        arr[jPlusOne] = temp;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return arr;
}

puts(fib(22));

let xs = [];
let k = 30;
while (k > 0) { push(xs, k); k = k - 1; }
bubbleSort(xs);
puts(xs[0]);
puts(xs[29]);
