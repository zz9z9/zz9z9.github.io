class Solution {
    public int[] solution(int[] numbers) {
        int size = numbers.length;
        boolean[] isExist = new boolean[201];
        int answerSize = 0;

        for(int i=0; i<size-1; i++) {
            int num1 = numbers[i];

            for(int j=i+1; j<size; j++) {
                int num2 = numbers[j];
                int sum = num1+num2;

                if(!isExist[sum]) {
                    isExist[sum] = true;
                    answerSize++;
                }
            }
        }

        int[] answer = new int[answerSize];
        int putIdx = 0;

        for(int i=0; i<isExist.length; i++) {
            if(isExist[i]) {
                answer[putIdx] = i;
                putIdx++;
            }
        }

        return answer;
    }
}
