// https://programmers.co.kr/learn/courses/30/lessons/42584

import java.util.Stack;

class Solution {
    public int[] solution(int[] prices) {
         int lastIdx = prices.length-1;
        int[] answer = new int[prices.length];
        Stack<int[]> stk = new Stack<>();

        answer[lastIdx] = 0;

        for(int i=lastIdx-1; i>=0; i--) {
            int currPrice = prices[i];
            int nextPrice = prices[i+1];

            if(currPrice > nextPrice) {
                // 1) 현재가격 > 다음가격
                answer[i] = 1;
                stk.push(new int[]{nextPrice, i+1});
            } else {
                // 2) 현재가격 <= 다음가격
                while(stk.size()>0 && stk.peek()[0] >= currPrice) {
                    stk.pop();
                }

                answer[i] = stk.isEmpty() ? (lastIdx - i) : (stk.peek()[1] - i);
                stk.push(new int[]{currPrice, i});
            }
        }

        return answer;
    }
}
