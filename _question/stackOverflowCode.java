// 왜 스택오버플로우 발생할까 ?? 

public class Main {

    static int[] dp = new int[60001];

    public static int solution(int n) {
        int answer = 0;
        int DIVIDER = 1000000007;

        if(dp[n]>0) {
            return dp[n];
        } else {
            answer = solution(n-1) + solution(n-2);
        }

        answer%=DIVIDER;
        dp[n] = answer;

        return answer;
    }

    public static void main(String[] args) {
        dp[1] = 1;
        dp[2] = 2;

        System.out.print(solution(60000));
    }
}
