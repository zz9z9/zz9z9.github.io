// https://programmers.co.kr/learn/courses/30/lessons/12899
class Solution {
    
    public String solution(int n) {
        String[] nums = {"4", "1", "2"};
        String answer = "";

        while(n>0) {
            int remainder = n%3;

            if(remainder==0) {
                n--;
            }

            n = n/3;
            answer = nums[remainder] + answer;
        }
        
        return answer;
    }
}
