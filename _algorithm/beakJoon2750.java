// https://www.acmicpc.net/source/21957085

import java.util.Arrays;
import java.util.Scanner;

public class Main {

    public static void main(String[] args) {

        Scanner sc = new Scanner(System.in);
        int numSize = sc.nextInt();
        Integer[] nums = new Integer[numSize];

        for(int i=0; i<numSize; i++) {
            nums[i] = sc.nextInt();
        }

        Arrays.sort(nums, (num1, num2) -> (num1 - num2));
        Arrays.stream(nums).forEach(System.out::println);
    }
}
